#!/usr/bin/env bash
set -euo pipefail

branch=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null || true)
fi

config_dir="${CLAUDE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/claude}"
account=$(jq -r '.oauthAccount.emailAddress // empty' "$config_dir/.claude.json" 2>/dev/null || true)

if [[ -n "$account" && "$account" == "${CLAUDE_STATUSLINE_WORK_EMAIL:-}" ]]; then
  account_label="WORK"
elif [[ -n "$account" && "$account" == "${CLAUDE_STATUSLINE_PRIVATE_EMAIL:-}" ]]; then
  account_label="PERSONAL"
else
  account_label="${account:-email unavailable}"
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
filter_path="${CLAUDE_STATUSLINE_JQ:-$script_dir/claude-statusline.jq}"

exec jq -r --arg branch "$branch" --arg account "$account_label" -f "$filter_path"
