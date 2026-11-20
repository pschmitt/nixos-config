#!/usr/bin/env bash

# xpanes() {
#   echo "Executing xpanes $*"
#   cd "$(readlink -f "$(dirname "$0")")" || exit 9
#   ./xpanes "$@"
# }

shortcuts() {
  case "$1" in
    system)
      if command -v termux-info >/dev/null
      then
        commands=(
          "sudo htop"
        )
      else
        commands=(
          htop
          "sudo nethogs"
          "watch -n 1 'df -h | grep -v /dev/loop' "
        )
      fi
      xpanes -l mv -t -ss -e "${commands[@]}"
      shift
      ;;
    *)
      xpanes "$@"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  shortcuts "$@"
fi
