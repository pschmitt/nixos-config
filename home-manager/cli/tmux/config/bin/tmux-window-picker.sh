#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0")
Select a tmux window with a live preview.
EOF
}

main() {
  local target

  if [[ -n "${1:-}" ]]
  then
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  fi

  target="$(
    tmux list-windows -a -F $'#{session_name}\t#{window_index}\t#{window_name}' |
      while IFS=$'\t' read -r session index window_name
      do
        printf '%s\t\033[1;38;5;75m%s\033[0m \033[2;38;5;244m#%s\033[0m  \033[1;38;5;221m%s\033[0m\n' \
          "$session:$index" "$session" "$index" "$window_name"
      done |
      fzf \
        --ansi \
        --delimiter=$'\t' \
        --with-nth='2..' \
        --color='spinner:-1' \
        --preview='
          while true
          do
            clear
            tmux capture-pane -ep -t {1}
            sleep 0.25
          done
        ' \
        --preview-window='right:70%,noinfo,<60(up,75%,noinfo)'
  )"

  if [[ -n "$target" ]]
  then
    target="${target%%$'\t'*}"
    tmux switch-client -t "$target"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
