#compdef svc
# zsh completion for svc: commands, --json, and the declared services
# (from `svc __names`) for the commands that take one.

_svc() {
  local -a commands services
  commands=(
    'list:List declared services and status'
    'status:Show a service and its last lines of output'
    'show:Show a service: state, PID, uptime, ports and settings'
    'start:Start a service'
    'stop:Stop a service'
    'restart:Restart a service'
    'logs:Show recent service output'
  )
  local -i first=2
  [[ ${words[2]} == --json ]] && first=3
  if (( CURRENT == 2 )); then
    _describe -t commands 'svc command' commands
    compadd -- --json
  elif (( CURRENT == first )); then
    _describe -t commands 'svc command' commands
  elif (( CURRENT == first + 1 )); then
    case ${words[first]} in
      status|show|start|stop|restart|logs)
        services=(${(f)"$(svc __names 2>/dev/null)"})
        _describe -t services 'service' services
        ;;
    esac
  fi
}

_svc "$@"
