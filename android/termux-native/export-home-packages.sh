#!/usr/bin/env bash

set -euo pipefail

manifest=${1:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF ELF-CLEANER API-LEVEL}
output=${2:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF ELF-CLEANER API-LEVEL}
readelf=${3:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF ELF-CLEANER API-LEVEL}
system_libraries=${4:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF ELF-CLEANER API-LEVEL}
patchelf=${5:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF ELF-CLEANER API-LEVEL}
elf_cleaner=${6:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF ELF-CLEANER API-LEVEL}
api_level=${7:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF ANDROID-SYSTEM-LIBRARIES PATCHELF ELF-CLEANER API-LEVEL}
launcher="$output/libexec/termux-native-launcher"

if [[ ! -x "$launcher" || ! -x "$readelf" || ! -d "$system_libraries" || ! -x "$patchelf" || ! -x "$elf_cleaner" ]]
then
  printf 'Termux launcher, ELF tools, or Android system library directory is missing.\n' >&2
  exit 1
fi

if [[ ! "$api_level" =~ ^[0-9]+$ ]]
then
  printf 'Invalid Android API level: %s\n' "$api_level" >&2
  exit 1
fi

normalize_elf() {
  local file=$1
  local dynamic_section

  if ! "$readelf" -h "$file" >/dev/null 2>&1
  then
    return 0
  fi

  chmod u+w "$file"
  dynamic_section=$("$readelf" -d "$file")
  if grep -Eq '\((RUNPATH|RPATH)\)' <<<"$dynamic_section"
  then
    # Nix build paths cannot exist on-device; the launcher supplies bundled
    # package libraries through LD_LIBRARY_PATH.
    "$patchelf" --remove-rpath "$file"
  fi
  "$elf_cleaner" --api-level "$api_level" "$file"
  chmod u-w "$file"
}

validate_elf() {
  local package=$1 file=$2 header program_headers dynamic_section interpreter
  header=$("$readelf" -h "$file") || {
    printf 'Cannot read ELF header for %s (%s).\n' "$package" "$file" >&2
    return 1
  }
  if ! grep -Eq 'Class:[[:space:]]+ELF64' <<<"$header" ||
    ! grep -Eq 'Machine:[[:space:]]+AArch64' <<<"$header"
  then
    printf 'Bundled ELF is not AArch64 ELF64: %s (%s)\n' "$package" "$file" >&2
    return 1
  fi

  program_headers=$("$readelf" -l "$file") || return
  interpreter=$(sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' <<<"$program_headers")
  if [[ -n "$interpreter" && "$interpreter" != /system/bin/linker64 ]]
  then
    printf 'Bundled ELF requests a non-Android interpreter: %s (%s): %s\n' \
      "$package" "$file" "$interpreter" >&2
    return 1
  fi

  dynamic_section=$("$readelf" -d "$file") || return
  if grep -Eq '\((RUNPATH|RPATH)\)' <<<"$dynamic_section"
  then
    printf 'Bundled ELF still has RPATH/RUNPATH: %s (%s)\n' "$package" "$file" >&2
    return 1
  fi
}

bundle_has_library() {
  local dependency=$1 candidate

  for candidate in \
    "$output"/native/*/lib/"$dependency" \
    "$output"/native/*/lib64/"$dependency" \
    "$output/lib/$dependency" \
    "$output/lib64/$dependency"
  do
    if [[ -f "$candidate" ]]
    then
      return 0
    fi
  done
  return 1
}

find_bundle_library() {
  local dependency=$1 directory candidate selected selected_hash candidate_hash
  local -a search_roots=() candidates=()

  for directory in "$output/lib" "$output/lib64" "$output"/native/*/lib "$output"/native/*/lib64
  do
    [[ -d "$directory" ]] && search_roots+=("$directory")
  done

  ((${#search_roots[@]})) || return 1
  while IFS= read -r -d '' candidate
  do
    candidates+=("$candidate")
  done < <(find "${search_roots[@]}" -type f -name "$dependency" -print0)

  ((${#candidates[@]})) || return 1
  selected=${candidates[0]}
  selected_hash=$(sha256sum "$selected")
  selected_hash=${selected_hash%% *}
  for candidate in "${candidates[@]:1}"
  do
    candidate_hash=$(sha256sum "$candidate")
    candidate_hash=${candidate_hash%% *}
    if [[ "$candidate_hash" != "$selected_hash" ]]
    then
      printf 'Ambiguous bundled library %s: %s and %s differ.\n' \
        "$dependency" "$selected" "$candidate" >&2
      return 2
    fi
  done

  printf '%s\n' "$selected"
}

apt_library_declared() {
  local dependency=$1 file=$2 package_name package

  case "$file" in
    "$output"/native/*) ;;
    *) return 1 ;;
  esac
  package_name=${file#"$output/native/"}
  package_name=${package_name%%/*}
  package=$(jq -c --arg name "$package_name" '.[] | select(.name == $name)' "$manifest") || return 1
  jq -e --arg dependency "$dependency" \
    '.aptLibraries | index($dependency) != null' <<<"$package" >/dev/null
}

if ! jq -e '
  type == "array" and
  all(.[];
    (.name | type == "string" and test("^[A-Za-z0-9._+-]+$")) and
    (.path | type == "string" and startswith("/nix/store/")) and
    (.runtimeClosure == null or (.runtimeClosure | type == "string" and startswith("/nix/store/"))) and
    (.abi == "android-bionic") and
    (.files | type == "array" and length > 0) and
    (.binaries | type == "array") and
    (.scripts | type == "array") and
    (.trees | type == "array") and
    (.aptPackages | type == "array" and all(.[]; type == "string" and test("^[A-Za-z0-9._+-]+$"))) and
    (.aptLibraries | type == "array" and all(.[]; type == "string" and test("^lib[A-Za-z0-9._+-]+\\.so(\\.[0-9]+)*$"))) and
    (.runtimeLibraries | type == "array" and all(.[]; type == "string" and test("^lib[A-Za-z0-9._+-]+\\.so(\\.[0-9]+)*$"))) and
    all(.files[]; type == "string") and
    all(.binaries[]; type == "string" and startswith("bin/")) and
    all(.scripts[]; type == "string" and startswith("bin/")) and
    all(.trees[]; type == "string") and
    ((.binaries + .scripts + .trees) | length > 0) and
    (.files as $files | all((.binaries + .scripts)[]; . as $command | $files | index($command) != null))
  )
' "$manifest" >/dev/null
then
  printf 'Invalid Termux-native package manifest: %s\n' "$manifest" >&2
  exit 1
fi

find_runtime_library() {
  local dependency=$1 runtime_closure=$2 root directory candidate
  local selected selected_hash candidate_hash
  local -a candidates=()

  [[ -n "$runtime_closure" && -f "$runtime_closure" ]] || return 1

  while IFS= read -r root
  do
    [[ -d "$root" ]] || continue
    for directory in "$root/lib" "$root/lib64" "$root/usr/lib" "$root/usr/lib64"
    do
      [[ -d "$directory" ]] || continue
      while IFS= read -r -d '' candidate
      do
        candidates+=("$candidate")
      done < <(find -L "$directory" -type f -name "$dependency" -print0)
    done
  done < "$runtime_closure"

  if (( ${#candidates[@]} == 0 ))
  then
    return 1
  fi

  selected=${candidates[0]}
  selected_hash=$(sha256sum "$selected")
  selected_hash=${selected_hash%% *}
  for candidate in "${candidates[@]:1}"
  do
    candidate_hash=$(sha256sum "$candidate")
    candidate_hash=${candidate_hash%% *}
    if [[ "$candidate_hash" != "$selected_hash" ]]
    then
      printf 'Ambiguous Android runtime library %s: %s and %s differ.\n' \
        "$dependency" "$selected" "$candidate" >&2
      return 2
    fi
  done

  printf '%s\n' "$selected"
}

bundle_dependencies() {
  local package=$1 binary=$2 file=$3 package_root=$4 runtime_closure=$5
  local dynamic_section dependency candidate destination

  if [[ -n "${scanned_elf[$file]:-}" ]]
  then
    return 0
  fi
  scanned_elf[$file]=1
  dynamic_section=$("$readelf" -d "$file")

  while IFS= read -r dependency
  do
    [[ -n "$dependency" ]] || continue
    if [[ ! "$dependency" =~ ^[A-Za-z0-9._+-]+$ ]]
    then
      printf 'Invalid shared library name for %s (%s): %s\n' \
        "$package" "$binary" "$dependency" >&2
      return 1
    fi
    if [[ -f "$system_libraries/$dependency" ]] || apt_library_declared "$dependency" "$file"
    then
      continue
    fi

    if [[ -f "$package_root/lib/$dependency" ]]
    then
      candidate="$package_root/lib/$dependency"
    elif [[ -f "$package_root/lib64/$dependency" ]]
    then
      candidate="$package_root/lib64/$dependency"
    elif candidate=$(find_bundle_library "$dependency")
    then
      :
    elif candidate=$(find_runtime_library "$dependency" "$runtime_closure")
    then
      destination="$package_root/lib/$dependency"
      mkdir -p "$(dirname "$destination")"
      cp -L -- "$candidate" "$destination"
      normalize_elf "$destination"
      candidate=$destination
    else
      printf 'Termux binary has an unavailable shared library: %s (%s): %s\n' \
        "$package" "$binary" "$dependency" >&2
      return 1
    fi

    if ! validate_elf "$package" "$candidate"
    then
      return 1
    fi
    bundle_dependencies "$package" "$binary" "$candidate" "$package_root" "$runtime_closure"
  done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' <<<"$dynamic_section")
}

declare -A scanned_elf=()

while IFS= read -r package
do
  name=$(jq -r '.name' <<<"$package")
  source_root=$(jq -r '.path' <<<"$package")
  runtime_closure=$(jq -r '.runtimeClosure // empty' <<<"$package")
  apt_libraries=$(jq -r 'if (.aptLibraries | length) > 0 then 1 else 0 end' <<<"$package")
  package_root="$output/native/$name"
  declare -A scanned_elf=()

  while IFS= read -r tree
  do
    if [[ ! "$tree" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]]
    then
      printf 'Unsafe package tree for %s: %s\\n' "$name" "$tree" >&2
      exit 1
    fi
    IFS=/ read -r -a components <<<"$tree"
    for component in "${components[@]}"
    do
      if [[ "$component" == . || "$component" == .. ]]
      then
        printf 'Unsafe package tree for %s: %s\\n' "$name" "$tree" >&2
        exit 1
      fi
    done
    source_tree="$source_root/$tree"
    destination_tree="$package_root/$tree"
    if [[ ! -d "$source_tree" ]]
    then
      printf 'Declared package tree is missing: %s (%s)\\n' "$name" "$tree" >&2
      exit 1
    fi
    mkdir -p "$destination_tree"
    cp -RL -- "$source_tree/." "$destination_tree/"
    while IFS= read -r -d '' tree_file
    do
      if "$readelf" -h "$tree_file" >/dev/null 2>&1
      then
        printf 'Native ELF in a data-only package tree: %s (%s)\\n' "$name" "$tree_file" >&2
        exit 1
      fi
      if grep -qF /nix/store "$tree_file"
      then
        printf 'Nix store reference in package tree: %s (%s)\\n' "$name" "$tree_file" >&2
        exit 1
      fi
    done < <(find "$destination_tree" -type f -print0)
  done < <(jq -r '.trees[]' <<<"$package")

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
    normalize_elf "$destination"
    if "$readelf" -h "$destination" >/dev/null 2>&1
    then
      validate_elf "$name" "$destination"
    fi
  done < <(jq -r '.files[]' <<<"$package")

  while IFS= read -r file
  do
    destination="$package_root/$file"
    if "$readelf" -h "$destination" >/dev/null 2>&1
    then
      bundle_dependencies "$name" "$file" "$destination" "$package_root" "$runtime_closure"
    fi
  done < <(jq -r '.files[]' <<<"$package")

  while IFS= read -r dependency
  do
    [[ -n "$dependency" ]] || continue
    if [[ -f "$system_libraries/$dependency" ]] ||
      jq -e --arg dependency "$dependency" '.aptLibraries | index($dependency) != null' <<<"$package" >/dev/null
    then
      continue
    fi
    if [[ -f "$package_root/lib/$dependency" ]]
    then
      candidate="$package_root/lib/$dependency"
    elif [[ -f "$package_root/lib64/$dependency" ]]
    then
      candidate="$package_root/lib64/$dependency"
    elif candidate=$(find_runtime_library "$dependency" "$runtime_closure")
    then
      destination="$package_root/lib/$dependency"
      mkdir -p "$(dirname "$destination")"
      cp -L -- "$candidate" "$destination"
      normalize_elf "$destination"
      candidate=$destination
    else
      printf 'Declared Termux runtime library is unavailable: %s: %s\n' "$name" "$dependency" >&2
      exit 1
    fi
    validate_elf "$name" "$candidate"
    bundle_dependencies "$name" "$dependency" "$candidate" "$package_root" "$runtime_closure"
  done < <(jq -r '.runtimeLibraries[]' <<<"$package")

  while IFS= read -r binary
  do
    source_file="$source_root/$binary"
    if [[ ! -f "$source_file" || ! -x "$source_file" ]]
    then
      printf 'Termux-native binary is missing or not executable: %s (%s)\n' "$name" "$binary" >&2
      exit 1
    fi
    bundled_file="$package_root/$binary"
    validate_elf "$name" "$bundled_file"
    dynamic_section=$("$readelf" -d "$bundled_file")
    program_headers=$("$readelf" -l "$bundled_file")
    interpreter=$(sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' <<<"$program_headers")
    bundle_dependencies "$name" "$binary" "$bundled_file" "$package_root" "$runtime_closure"
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
    printf '%s %s %s\n' "$name" "$binary" "$apt_libraries" > "$output/launchers/$command"
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
    script_interpreter=$(head -n 1 "$source_file")
    if [[ "$script_interpreter" != '#!/data/data/com.termux/files/usr/bin/sh' &&
      "$script_interpreter" != '#!/data/data/com.termux/files/usr/bin/bash' ]]
    then
      printf 'Termux-native script must use the Termux sh or bash interpreter: %s (%s)\n' "$name" "$script" >&2
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

  while IFS= read -r -d '' bundled_file
  do
    if "$readelf" -h "$bundled_file" >/dev/null 2>&1
    then
      relative_file=${bundled_file#"$package_root"/}
      validate_elf "$name" "$bundled_file"
      bundle_dependencies "$name" "$relative_file" "$bundled_file" "$package_root" "$runtime_closure"
    fi
  done < <(find "$package_root" -type f -print0)
done < <(jq -c '.[]' "$manifest")

while IFS= read -r -d '' bundled_file
do
  if "$readelf" -h "$bundled_file" >/dev/null 2>&1
  then
    validate_elf 'bundle' "$bundled_file"
    case "$bundled_file" in
      "$output/native/"*) continue ;;
    esac
    bundle_dependencies 'bundle' "$bundled_file" "$bundled_file" "$output" ''
  fi
done < <(find "$output/lib" "$output/lib64" -type f -print0 2>/dev/null)

while IFS= read -r -d '' bundled_file
do
  if [[ -L "$bundled_file" ]]
  then
    resolved_file=$(realpath -e -- "$bundled_file") || {
      printf 'Broken symlink in Termux bundle: %s\n' "$bundled_file" >&2
      exit 1
    }
    case "$resolved_file" in
      "$output"/*) ;;
      *)
        printf 'Symlink escapes the Termux bundle: %s -> %s\n' \
          "$bundled_file" "$resolved_file" >&2
        exit 1
        ;;
    esac
  else
    resolved_file=$bundled_file
  fi

  if "$readelf" -h "$resolved_file" >/dev/null 2>&1
  then
    validate_elf 'bundle' "$resolved_file"
    dynamic_section=$("$readelf" -d "$resolved_file")
    while IFS= read -r dependency
    do
      [[ -n "$dependency" ]] || continue
      if [[ -f "$system_libraries/$dependency" ]] || bundle_has_library "$dependency" ||
        apt_library_declared "$dependency" "$bundled_file"
      then
        continue
      fi
      printf 'Bundled ELF has an unavailable shared library: %s: %s\n' \
        "$bundled_file" "$dependency" >&2
      exit 1
    done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' <<<"$dynamic_section")
  fi
done < <(find "$output" \( -type f -o -type l \) -print0)

# vim: set ft=sh et ts=2 sw=2 :
