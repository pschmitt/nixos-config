#!/usr/bin/env bash
# PostToolUse hook (Claude Code and Codex): safety net for credentials that got into
# a tool result despite agent-secret-guard. gitleaks finds them (its default rules
# plus pkgs/local/agent-secret-scan/gitleaks.toml). MCP results are masked before the
# model sees them; for every tool the agent is told to run the leaked-credentials
# procedure.

input="$(cat)"

response="$(jq -c '.tool_response // empty' <<<"$input" 2>/dev/null || true)"
[[ -n "$response" ]] || exit 0

# Plain text for the scanner: every string of the response on its own line.
text="$(jq -r '.. | strings' <<<"$response" 2>/dev/null || true)"
[[ -n "$text" ]] || exit 0

findings="$(gitleaks stdin --config "$AGENT_SECRET_SCAN_RULES" --no-banner --no-color \
  --log-level error --exit-code 0 --report-format json --report-path /dev/stdout \
  <<<"$text" 2>/dev/null || true)"
[[ -n "$findings" && "$findings" != "[]" ]] || exit 0

found="$(jq -r '[.[].RuleID] | unique | join(", ")' <<<"$findings" 2>/dev/null || true)"
[[ -n "$found" ]] || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$input")"
context="A tool result from ${tool} appears to contain credentials (rules: ${found}). Load the leaked-credentials skill and follow it: tell the user what leaked and where, add a row to the Obsidian note homelab/🚨 Leaked credentials.md without the value, and do not repeat the value."

# Only Claude Code accepts rewritten MCP output; Codex gets the warning alone.
if [[ "$tool" == mcp__* && -n "${CLAUDECODE:-}" ]]
then
  updated="$(jq -c --argjson findings "$findings" '
    ($findings | map(.Secret) | map(select(length > 0)) | unique) as $secrets
    | walk(if type == "string"
           then reduce $secrets[] as $s (.; split($s) | join("[REDACTED]"))
           else . end)' <<<"$response")"
  jq -n --arg context "$context" --argjson updated "$updated" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context, updatedMCPToolOutput: $updated}}'
else
  jq -n --arg context "$context" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
fi
