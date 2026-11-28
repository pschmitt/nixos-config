# bash completion for svc: commands, --json, and the declared services
# (from `svc __names`) for the commands that take one.
_svc() {
  local cur=${COMP_WORDS[COMP_CWORD]} first=1
  [[ ${COMP_WORDS[1]} == --json ]] && first=2
  local commands="list status show start stop restart logs"
  if ((COMP_CWORD == 1)); then
    mapfile -t COMPREPLY < <(compgen -W "--json $commands" -- "$cur")
  elif ((COMP_CWORD == first)); then
    mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
  elif ((COMP_CWORD == first + 1)); then
    case ${COMP_WORDS[first]} in
      status | show | start | stop | restart | logs)
        mapfile -t COMPREPLY < <(compgen -W "$(svc __names 2>/dev/null)" -- "$cur")
        ;;
    esac
  fi
}
complete -F _svc svc
