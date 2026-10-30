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
# claude-work profile. Agents that set no AI_AGENT are recognized by what they set
# themselves, which beats an inherited AI_AGENT (an agent started from another):
# Antigravity (ANTIGRAVITY_AGENT), OpenCode (OPENCODE), Gemini CLI (GEMINI_CLI),
# Codex (CODEX_*). Failing those, the MCP client's own name (BROWSER_MCP_CLIENT,
# its `initialize`), e.g. "gemini-cli-mcp-client" -> "gemini-cli".
agent_label() {
  local label="" name="" rest="" version=""

  if [[ -n "${ANTIGRAVITY_AGENT:-}" ]]
  then
    label="agy"
  elif [[ -n "${OPENCODE:-}" ]]
  then
    label="opencode"
  elif [[ -n "${GEMINI_CLI:-}" ]]
  then
    label="gemini-cli"
  elif [[ -n "${CODEX_THREAD_ID:-}${CODEX_SESSION_ID:-}${CODEX_SANDBOX:-}" ]]
  then
    label="codex"
  elif [[ -n "${AI_AGENT:-}" ]]
  then
    name="${AI_AGENT%%_*}"
    rest="${AI_AGENT#*_}"
    version="${rest%%_*}"
    label="$name"
    if [[ "$rest" != "$AI_AGENT" && -n "$version" ]]
    then
      label="$name ${version//-/.}"
    fi
  elif [[ -n "${BROWSER_MCP_CLIENT:-}" ]]
  then
    label="${BROWSER_MCP_CLIENT%-mcp-client}"
    label="${label%-client}"
  fi

  if [[ "$label" == claude* && "${CLAUDE_CONFIG_DIR:-}" == */claude-work ]]
  then
    label="$label (work)"
  fi

  printf '%s' "$label"
}

conversation_id() {
  printf '%s' "${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-${ANTIGRAVITY_CONVERSATION_ID:-}}}}"
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

  # The endpoint carries a signed token. Pass it through the environment, not
  # --cdp-endpoint: process listings (ps, pgrep -a) would print it.
  export PLAYWRIGHT_MCP_CDP_ENDPOINT="${endpoint}${sep}${query}"
  exec playwright-mcp --output-dir="$output_dir"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
