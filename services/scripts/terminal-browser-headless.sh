#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") open [URL|FILE] [terminal-browser open options]
       $(basename "$0") ls
       $(basename "$0") action [--browser KEY] [--tab ID] -- COMMAND...

Runs terminal-browser inside a headless kitty (see the
terminal-browser-headless user services), for agents without a graphical
terminal. "open" starts the services on demand and opens the browser in a
new kitty window; every other subcommand is passed to terminal-browser.

Use "ls" to get the browser KEY, then
"action --browser KEY -- snapshot" to drive it.
EOF
}

find_socket() {
  local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  local socks=()
  local _

  shopt -s nullglob
  for _ in {1..50}
  do
    socks=("${runtime}"/terminal-browser-kitty.sock*)
    if [[ -n "${socks[0]:-}" ]]
    then
      printf '%s\n' "${socks[0]}"
      return 0
    fi
    sleep 0.2
  done

  printf 'kitty remote control socket did not appear in %s\n' "${runtime}" >&2
  return 1
}

open_browser() {
  local sock

  systemctl --user start terminal-browser-kitty.service || return 1
  sock="$(find_socket)" || return 1

  kitten @ --to "unix:${sock}" launch --type=os-window \
    terminal-browser open "$@" > /dev/null
}

main() {
  case "${1:-}" in
    -h|--help|"")
      usage
      return 0
      ;;
    open)
      shift
      open_browser "$@"
      ;;
    *)
      terminal-browser "$@"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
