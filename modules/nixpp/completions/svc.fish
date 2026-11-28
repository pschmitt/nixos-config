# fish completion for svc: commands, --json, and the declared services
# (from `svc __names`) for the commands that take one.
set -l commands list status show start stop restart logs
complete -c svc -f
complete -c svc -n "not __fish_seen_subcommand_from $commands" -l json -d 'JSON output'
complete -c svc -n "not __fish_seen_subcommand_from $commands" -a list -d 'List declared services and status'
complete -c svc -n "not __fish_seen_subcommand_from $commands" -a status -d 'Show a service and its last output'
complete -c svc -n "not __fish_seen_subcommand_from $commands" -a show -d 'Show a service'
complete -c svc -n "not __fish_seen_subcommand_from $commands" -a start -d 'Start a service'
complete -c svc -n "not __fish_seen_subcommand_from $commands" -a stop -d 'Stop a service'
complete -c svc -n "not __fish_seen_subcommand_from $commands" -a restart -d 'Restart a service'
complete -c svc -n "not __fish_seen_subcommand_from $commands" -a logs -d 'Show recent service output'
complete -c svc -n "__fish_seen_subcommand_from status show start stop restart logs" -a '(svc __names 2>/dev/null)' -d service
