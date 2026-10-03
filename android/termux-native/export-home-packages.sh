#!/usr/bin/env bash

set -euo pipefail

manifest=${1:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF}
output=${2:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF}
readelf=${3:?usage: export-home-packages.sh MANIFEST OUTPUT LLVM-READELF}
launcher="$output/libexec/termux-native-launcher"

if [[ ! -x "$launcher" ]]
then
  printf 'Termux launcher binary is missing: %s\n' "$launcher" >&2
  exit 1
fi

if ! jq -e '
  type == "array" and
  all(.[];
    (.name | type == "string" and test("^[A-Za-z0-9._+-]+$")) and
    (.path | type == "string" and startswith("/nix/store/")) and
    (.files | type == "array" and length > 0) and
    (.binaries | type == "array" and length > 0) and
    all(.files[]; type == "string") and
    all(.binaries[]; type == "string" and startswith("bin/")) and
    (.files as $files | all(.binaries[]; . as $binary | $files | index($binary) != null))
  )
' "$manifest" >/dev/null
then
  printf 'Invalid Termux-native package manifest: %s\n' "$manifest" >&2
  exit 1
fi

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

  while IFS= read -r binary
  do
    source_file="$source_root/$binary"
    if [[ ! -f "$source_file" || ! -x "$source_file" ]]
    then
      printf 'Termux-native binary is missing or not executable: %s (%s)\n' "$name" "$binary" >&2
      exit 1
    fi
    header=$("$readelf" -h "$source_file")
    if ! grep -Eq 'Class:[[:space:]]+ELF64' <<<"$header" ||
      ! grep -Eq 'Machine:[[:space:]]+AArch64' <<<"$header"
    then
      printf 'Termux binary is not AArch64 ELF64: %s (%s)\n' "$name" "$binary" >&2
      exit 1
    fi

    program_headers=$("$readelf" -l "$source_file")
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
done < <(jq -c '.[]' "$manifest")
