#!/usr/bin/env bash

set -euo pipefail

manifest=${1:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF}
output=${2:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF}
readelf=${3:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF}
system_libraries=${4:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF}
patchelf=${5:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF}
launcher="$output/libexec/termux-native-launcher"

if [[ ! -x "$launcher" || ! -x "$readelf" || ! -d "$system_libraries" || ! -x "$patchelf" ]]
then
  printf 'Termux launcher or Android system library directory is missing.\n' >&2
  exit 1
fi

if ! jq -e '
  type == "array" and
  all(.[];
    (.name | type == "string" and test("^[A-Za-z0-9._+-]+$")) and
    (.path | type == "string" and startswith("/nix/store/")) and
    (.files | type == "array" and length > 0) and
    (.binaries | type == "array" and length > 0) and
    (.scripts | type == "array") and
    all(.files[]; type == "string") and
    all(.binaries[]; type == "string" and startswith("bin/")) and
    all(.scripts[]; type == "string" and startswith("bin/")) and
    (.files as $files | all((.binaries + .scripts)[]; . as $command | $files | index($command) != null))
  )
' "$manifest" >/dev/null
then
  printf 'Invalid Termux-native package manifest: %s\n' "$manifest" >&2
  exit 1
fi

declare -A checked_elfs=()

check_elf_dependencies() {
  local package=$1 package_root=$2 elf_file=$3 relative dependency candidate
  local header program_headers interpreter dynamic_section

  header=$("$readelf" -h "$elf_file" 2>/dev/null) || return 0
  if [[ -n "${checked_elfs[$elf_file]:-}" ]]
  then
    return 0
  fi
  checked_elfs[$elf_file]=1

  relative=${elf_file#"$package_root/"}
  if ! grep -Eq 'Class:[[:space:]]+ELF64' <<<"$header" ||
    ! grep -Eq 'Machine:[[:space:]]+AArch64' <<<"$header"
  then
    printf 'Exported ELF is not AArch64 ELF64: %s (%s)\n' "$package" "$relative" >&2
    return 1
  fi

  program_headers=$("$readelf" -l "$elf_file") || return
  interpreter=$(sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' <<<"$program_headers")
  if [[ -n "$interpreter" && "$interpreter" != /system/bin/linker64 ]]
  then
    printf 'Exported ELF requests a non-Android interpreter: %s (%s): %s\n' \
      "$package" "$relative" "$interpreter" >&2
    return 1
  fi

  dynamic_section=$("$readelf" -d "$elf_file" 2>/dev/null || true)
  while IFS= read -r dependency
  do
    [[ -n "$dependency" ]] || continue
    if [[ ! "$dependency" =~ ^[A-Za-z0-9._+-]+$ ]]
    then
      printf 'Invalid shared library name for %s (%s): %s\n' \
        "$package" "$relative" "$dependency" >&2
      return 1
    fi
    if [[ -f "$system_libraries/$dependency" ]]
    then
      continue
    fi

    candidate=''
    for candidate in "$package_root/lib/$dependency" "$package_root/lib64/$dependency"
    do
      if [[ -f "$candidate" ]]
      then
        check_elf_dependencies "$package" "$package_root" "$candidate" || return
        candidate='found'
        break
      fi
    done
    if [[ "$candidate" != found ]]
    then
      printf 'Exported ELF has an unavailable shared library: %s (%s): %s\n' \
        "$package" "$relative" "$dependency" >&2
      return 1
    fi
  done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' <<<"$dynamic_section")
}

while IFS= read -r package
do
  name=$(jq -r '.name' <<<"$package")
  source_root=$(jq -r '.path' <<<"$package")
  package_root="$output/native/$name"

  while IFS= read -r file
  do
    if [[ ! "$file" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]]
    then
      printf 'Unsafe package path for %s: %s\n' "$name" "$file" >&2
      exit 1
    fi

    IFS=/ read -r -a components <<<"$file"
    for component in "${components[@]}"
    do
      if [[ "$component" == . || "$component" == .. ]]
      then
        printf 'Unsafe package path for %s: %s\n' "$name" "$file" >&2
        exit 1
      fi
    done

    source_file="$source_root/$file"
    if [[ ! -f "$source_file" || -L "$source_file" && ! -e "$source_file" ]]
    then
      printf 'Declared package file is missing: %s (%s)\n' "$name" "$file" >&2
      exit 1
    fi
    destination="$package_root/$file"
    mkdir -p "$(dirname "$destination")"
    cp -L -- "$source_file" "$destination"
  done < <(jq -r '.files[]' <<<"$package")

  checked_elfs=()
  while IFS= read -r -d '' shipped_file
  do
    check_elf_dependencies "$name" "$package_root" "$shipped_file"
  done < <(find "$package_root" -type f -print0)

  while IFS= read -r binary
  do
    source_file="$source_root/$binary"
    if [[ ! -f "$source_file" || ! -x "$source_file" ]]
    then
      printf 'Termux-native binary is missing or not executable: %s (%s)\n' "$name" "$binary" >&2
      exit 1
    fi
    bundled_file="$package_root/$binary"
    dynamic_section=$("$readelf" -d "$bundled_file")
    if grep -Eq '\((RUNPATH|RPATH)\)' <<<"$dynamic_section"
    then
      # Nix build paths cannot exist on-device. The launcher supplies the
      # package-local library directory through LD_LIBRARY_PATH instead.
      chmod u+w "$bundled_file"
      "$patchelf" --remove-rpath "$bundled_file"
      chmod u-w "$bundled_file"
    fi

    header=$("$readelf" -h "$bundled_file")
    if ! grep -Eq 'Class:[[:space:]]+ELF64' <<<"$header" ||
      ! grep -Eq 'Machine:[[:space:]]+AArch64' <<<"$header"
    then
      printf 'Termux binary is not AArch64 ELF64: %s (%s)\n' "$name" "$binary" >&2
      exit 1
    fi

    program_headers=$("$readelf" -l "$bundled_file")
    interpreter=$(sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' <<<"$program_headers")
    if [[ -n "$interpreter" && "$interpreter" != /system/bin/linker64 ]]
    then
      printf 'Termux binary requests a non-Android interpreter: %s (%s): %s\n' \
        "$name" "$binary" "$interpreter" >&2
      exit 1
    fi
    dynamic_section=$("$readelf" -d "$source_file")
    if [[ -z "$interpreter" ]] && grep -Eq '\((NEEDED|RUNPATH|RPATH)\)' <<<"$dynamic_section"
    then
      printf 'Static Termux binary has dynamic dependencies: %s (%s)\n' "$name" "$binary" >&2
      exit 1
    fi

    command=${binary##*/}
    launcher="$output/bin/$command"
    if [[ -e "$launcher" ]]
    then
      printf 'Termux-native command collision: %s\n' "$command" >&2
      exit 1
    fi
    mkdir -p "$output/bin" "$output/launchers"
    printf '%s %s\n' "$name" "$binary" > "$output/launchers/$command"
    cp -- "$output/libexec/termux-native-launcher" "$launcher"
    chmod 0755 "$launcher"
  done < <(jq -r '.binaries[]' <<<"$package")

  while IFS= read -r script
  do
    source_file="$source_root/$script"
    command=${script##*/}
    launcher="$output/bin/$command"
    if [[ ! -f "$source_file" || ! -x "$source_file" ]]
    then
      printf 'Termux-native script is missing or not executable: %s (%s)\n' "$name" "$script" >&2
      exit 1
    fi
    if [[ "$(head -n 1 "$source_file")" != '#!/data/data/com.termux/files/usr/bin/sh' ]]
    then
      printf 'Termux-native script must use the Termux sh interpreter: %s (%s)\n' "$name" "$script" >&2
      exit 1
    fi
    if grep -qF /nix/store "$source_file"
    then
      printf 'Termux-native script contains a Nix store path: %s (%s)\n' "$name" "$script" >&2
      exit 1
    fi
    if [[ -e "$launcher" ]]
    then
      printf 'Termux-native command collision: %s\n' "$command" >&2
      exit 1
    fi
    cp -- "$source_file" "$launcher"
    chmod 0755 "$launcher"
  done < <(jq -r '.scripts[]' <<<"$package")
done < <(jq -c '.[]' "$manifest")
