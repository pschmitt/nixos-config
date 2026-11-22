#!/usr/bin/env bash

usage() {
  local bold='' reset=''
  if [[ -z ${NO_COLOR:-} ]] && { [[ ${CLICOLOR_FORCE:-0} != 0 ]] || [[ -t 1 && ${TERM:-} != dumb ]]; }
  then
    bold=$'\033[1;36m'
    reset=$'\033[0m'
  fi
  printf '%s\n' \
    "${bold}Usage:${reset} tpp app COMMAND [ARGS...]" \
    '' \
    "${bold}Commands:${reset}" \
    '  update   Update or check the TermuxPP app' \
    '  restart --yes  Restart TermuxPP, ending all terminal sessions'
}

main() {
  local command=${1:-}
  if (($# > 0))
  then
    shift
  fi
  case "$command" in
    ''|-h|--help|help)
      usage
      ;;
    __complete)
      if (($# > 1)) && [[ $1 == update ]]
      then
        shift
        exec "$TPP_APP_UPDATE" __complete "$@"
      fi
      if (($# == 2)) && [[ $1 == restart ]]
      then
        for option in --yes --help
        do
          [[ $option != "$2"* ]] || printf '%s\n' "$option"
        done
        return 0
      fi
      if (($# > 1))
      then
        return 0
      fi
      case "${1:-}" in
        '') printf '%s\n' update restart --help ;;
        u*) printf '%s\n' update ;;
        r*) printf '%s\n' restart ;;
        -*) printf '%s\n' --help ;;
      esac
      ;;
    update)
      exec "$TPP_APP_UPDATE" "$@"
      ;;
    restart)
      if [[ ${1:-} == --help || ${1:-} == -h ]]
      then
        printf '%s\n' 'Usage: tpp app restart --yes' 'Restart TermuxPP and end all terminal sessions.'
        return 0
      fi
      if (($# != 1)) || [[ $1 != --yes ]]
      then
        printf '%s\n' 'tpp app restart ends all terminal sessions. To proceed, run tpp app restart --yes.' >&2
        return 2
      fi
      printf '%s\n' 'Restarting TermuxPP; all terminal sessions will end.' >&2
      tpp-am startservice --user "${TERMUX__USER_ID:-0}" \
        -n dev.pschmitt.termux/com.termux.app.TermuxService \
        -a dev.pschmitt.termux.service_kill \
        --ez dev.pschmitt.termux.KILL_RESTART true
      ;;
    *)
      printf 'tpp app: unknown command: %s\n' "$command" >&2
      return 2
      ;;
  esac
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
