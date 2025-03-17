#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

usage() {
  echo "Usage: $0 [OPTIONS] [TOFU_APPLY_OPTIONS]"
  echo "  -i, --ignore PATTERN  Ignore the pattern"
  echo "  --nix                 Ignore module.nix"
}

join_by_pipe() {
  local IFS="|"
  echo "$*"
}

PATTERNS=()

while [[ -n $* ]]
do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --nix|--no-nix|--nonix)
      PATTERNS+=('module\.nix')
      shift
      ;;
    -i|--ignore|-f|--filter)
      PATTERNS+=("$2")
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

GREP_PATTERN=$(join_by_pipe "${PATTERNS[@]}")
echo "FILTER PATTERN: $GREP_PATTERN"

TARGETS=()
for obj in $(./tofu.sh state ls | grep -vE -- "$GREP_PATTERN")
do
  TARGETS+=("-target=${obj}")
done

./tofu.sh apply "${TARGETS[@]}" "$@"
