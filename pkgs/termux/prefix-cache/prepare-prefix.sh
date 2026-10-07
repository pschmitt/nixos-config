#!/usr/bin/env bash

set -Eeuo pipefail

if (($# != 2))
then
  printf 'Usage: %s BOOTSTRAP_ZIP OUTPUT_DIRECTORY\n' "$(basename "$0")" >&2
  exit 2
fi

bootstrap_zip=$1
output_dir=$2
stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/termux-prefix.XXXXXXXX")
prefix_dir="$stage_dir/usr"
symlink_manifest="$prefix_dir/SYMLINKS.txt"

mkdir -p "$prefix_dir"
unzip -qq "$bootstrap_zip" -d "$prefix_dir"
if [[ ! -f "$symlink_manifest" ]]
then
  printf 'Termux bootstrap is missing its SYMLINKS.txt manifest\n' >&2
  exit 1
fi

while IFS= read -r entry || [[ -n "$entry" ]]
do
  [[ -n "$entry" ]] || continue
  if [[ "$entry" != *'←'* ]]
  then
    printf 'Malformed Termux symlink entry: %s\n' "$entry" >&2
    exit 1
  fi

  target=${entry%%←*}
  relative_path=${entry#*←}
  if [[ -z "$target" || "$relative_path" != ./* ]]
  then
    printf 'Unsafe Termux symlink entry: %s\n' "$entry" >&2
    exit 1
  fi

  relative_path=${relative_path#./}
  case "/$relative_path/" in
    *"/../"* | *"//"*)
      printf 'Termux symlink path escapes the prefix: %s\n' "$entry" >&2
      exit 1
      ;;
  esac

  destination="$prefix_dir/$relative_path"
  if [[ -e "$destination" || -L "$destination" ]]
  then
    printf 'Termux symlink collides with an archive entry: %s\n' "$entry" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$destination")"
  ln -s -- "$target" "$destination"
done < "$symlink_manifest"

unlink "$symlink_manifest"
mkdir -p "$output_dir/share/termux"
tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
  -C "$stage_dir" -cf - usr | gzip -n > "$output_dir/share/termux/termux-prefix.tar.gz"
