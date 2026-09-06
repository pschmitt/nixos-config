#!/usr/bin/env bash
# Report whether an xdg-desktop-portal screencast is live, and which clients
# are attached to it.
#
# A portal capture shows up in the PipeWire graph as a link with one endpoint
# on an xdg-desktop-portal node; the other endpoint names the capturing client.
# This is how the pschmitt/screencast Noctalia plugin detects it, and it needs
# nothing running in the background - no D-Bus watcher, no shared state file.

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Report live xdg-desktop-portal screencasts, read from the PipeWire graph.

Options:
  -j, --json    Print {"active": bool, "apps": [...]} (default)
  -a, --apps    Print the capturing client names, one per line
  -c, --check   Print nothing; exit 0 while screencasting, 1 otherwise
  -h, --help    Show this help
EOF
}

# JSON array of the PipeWire node names linked to an xdg-desktop-portal node.
screencasting_apps() {
  pw-dump 2>/dev/null | jq -c '
    [ .[] | select(.type == "PipeWire:Interface:Node") ] as $nodes
    | ( [ $nodes[] | { key: (.id | tostring), value: (.info.props["node.name"] // "") } ] | from_entries ) as $names
    | ( [ $nodes[] | select((.info.props["node.name"] // "") | test("xdg-desktop-portal")) | .id ] ) as $portal
    | [ .[]
        | select(.type == "PipeWire:Interface:Link")
        | [ .info["output-node-id"], .info["input-node-id"] ]
        # A portal link has one portal endpoint and one client endpoint;
        # report the latter.
        | select(any(.[]; IN($portal[])))
        | .[]
        | select(IN($portal[]) | not)
      ]
    | map($names[tostring] // "")
    | map(select(. != ""))
    | unique
  '
}

apps_or_empty() {
  local apps

  if ! apps="$(screencasting_apps)" || [[ -z "$apps" ]]
  then
    apps="[]"
  fi

  printf '%s\n' "$apps"
}

print_json() {
  jq -nc --argjson apps "$(apps_or_empty)" \
    '{active: (($apps | length) > 0), apps: $apps}'
}

print_apps() {
  jq -r '.[]' <<< "$(apps_or_empty)"
}

check() {
  jq -e 'length > 0' <<< "$(apps_or_empty)" > /dev/null
}

main() {
  local action=json

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      -j|--json)
        action=json
        shift
        ;;
      -a|--apps)
        action=apps
        shift
        ;;
      -c|--check)
        action=check
        shift
        ;;
      --trace)
        set -x
        shift
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  case "$action" in
    json)
      print_json
      ;;
    apps)
      print_apps
      ;;
    check)
      check
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
