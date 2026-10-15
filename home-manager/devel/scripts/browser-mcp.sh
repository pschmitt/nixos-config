#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") ENDPOINT OUTPUT_DIR

Start the Playwright MCP on a browser-daemon node's CDP ENDPOINT
(wss://.../chromium), telling the node which agent uses it: the agent and
its version, Claude's profile, the conversation id, the project directory and
this machine. The node's dashboard shows it on the session.
EOF
}

# claude-code_2-1-296_harness -> "claude-code 2.1.296"; plus "(work)" for the
# claude-work profile. Codex sets no AI_AGENT: recognized by its variables.
agent_label() {
  local label="" name="" rest="" version=""

  if [[ -n "${AI_AGENT:-}" ]]
  then
    name="${AI_AGENT%%_*}"
    rest="${AI_AGENT#*_}"
    version="${rest%%_*}"
    label="$name"
    if [[ "$rest" != "$AI_AGENT" && -n "$version" ]]
    then
      label="$name ${version//-/.}"
    fi
  elif [[ -n "${CODEX_THREAD_ID:-}${CODEX_SESSION_ID:-}${CODEX_SANDBOX:-}" ]]
  then
    label="codex"
  fi

  if [[ -n "$label" && "${CLAUDE_CONFIG_DIR:-}" == */claude-work ]]
  then
    label="$label (work)"
  fi

  printf '%s' "$label"
}

conversation_id() {
  printf '%s' "${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-}}}"
}

uri() {
  jq -rn --arg v "$1" '$v | @uri'
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
  esac

  if [[ -z "${1:-}" || -z "${2:-}" ]]
  then
    usage >&2
    return 2
  fi

  local endpoint="$1"
  local output_dir="$2"
  local query
  local sep="?"

  query="agent=$(uri "$(agent_label)")"
  query+="&conversation=$(uri "$(conversation_id)")"
  query+="&cwd=$(uri "$PWD")"
  query+="&machine=$(uri "$(uname -n)")"

  # The endpoint may already carry a query, e.g. ?profile=work
  if [[ "$endpoint" == *\?* ]]
  then
    sep="&"
  fi

  exec playwright-mcp --cdp-endpoint="${endpoint}${sep}${query}" --output-dir="$output_dir"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
