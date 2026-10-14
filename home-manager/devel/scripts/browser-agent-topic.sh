#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") TOPIC

Label this agent conversation's browser sessions with TOPIC (a few words on
what it is doing), shown on the browser-daemon dashboard. Applies to every
node this conversation is connected to through a browser MCP.

The nodes come from BROWSER_AGENT_NODES (space-separated base URLs).
EOF
}

conversation_id() {
  printf '%s' "${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-}}}"
}

set_topic() {
  local node="$1"
  local body="$2"
  local matched

  if ! matched=$(curl --silent --show-error --fail --max-time 10 \
    -H 'Content-Type: application/json' --data "$body" \
    "${node}/api/agent-topic" | jq -r '.clients')
  then
    printf '%s: not reachable\n' "$node" >&2
    return 1
  fi

  if [[ "$matched" != "0" ]]
  then
    printf '%s: %s connection(s) labelled\n' "$node" "$matched"
  fi
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
  esac

  if [[ -z "${1:-}" ]]
  then
    usage >&2
    return 2
  fi

  local conversation
  conversation="$(conversation_id)"
  if [[ -z "$conversation" ]]
  then
    printf 'No agent conversation id in the environment (CLAUDE_CODE_SESSION_ID, CODEX_THREAD_ID)\n' >&2
    return 2
  fi

  local body node
  body=$(jq -cn --arg c "$conversation" --arg t "$*" '{conversation: $c, topic: $t}')

  for node in ${BROWSER_AGENT_NODES:-}
  do
    set_topic "$node" "$body" || true
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
