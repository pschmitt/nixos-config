#!/usr/bin/env bash
# PostToolUse hook (Claude Code and Codex): safety net for credentials that got into a tool result despite
# agent-secret-guard. MCP results are masked before the model sees them; for every
# tool the agent is told to run the leaked-credentials procedure.

input="$(cat)"

# shellcheck disable=SC2016  # jq program, not shell
# One jq program for matching and masking. Classes are named so the warning says
# what leaked without repeating the value.
mask='
  def patterns: [
    ["GitHub token", "gh[pousr]_[A-Za-z0-9]{30,}"],
    ["GitLab token", "glpat-[A-Za-z0-9_-]{20,}"],
    ["API key", "sk-[A-Za-z0-9_-]{20,}"],
    ["JWT", "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{5,}"],
    ["age secret key", "AGE-SECRET-KEY-1[A-Z0-9]{20,}"],
    ["private key block", "-----BEGIN [A-Z ]*PRIVATE KEY-----"],
    ["credential parameter", "(?i)(access_token|refresh_token|token|api[_-]?key|passwd|password|secret)=[^&\\s\"'"'"'$<{(\\[][^&\\s\"'"'"']{7,}"]
  ];
  def classes: tostring as $t | [patterns[] | select(. as $p | $t | test($p[1])) | .[0]] | unique;
  def masked: reduce patterns[] as $p (.; gsub($p[1]; "[REDACTED]"));
'

response="$(jq -c '.tool_response // empty' <<<"$input" 2>/dev/null || true)"
[[ -n "$response" ]] || exit 0

found="$(jq -r "$mask"' classes | join(", ")' <<<"$response" 2>/dev/null || true)"
[[ -n "$found" ]] || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$input")"
context="A tool result from ${tool} appears to contain credentials (${found}). Follow the Leaked credentials rule: tell the user what leaked and where, add a row to the Obsidian note homelab/🚨 Leaked credentials.md without the value, and do not repeat the value."

# Only Claude Code accepts rewritten MCP output; Codex gets the warning alone.
if [[ "$tool" == mcp__* && -n "${CLAUDECODE:-}" ]]
then
  updated="$(jq -c "$mask"' walk(if type == "string" then masked else . end)' <<<"$response")"
  jq -n --arg context "$context" --argjson updated "$updated" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context, updatedMCPToolOutput: $updated}}'
else
  jq -n --arg context "$context" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
fi
