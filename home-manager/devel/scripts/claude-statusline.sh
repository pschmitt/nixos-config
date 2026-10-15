#!/usr/bin/env bash
set -euo pipefail

branch=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null || true)
fi

profile="${CLAUDE_PROFILE:-personal}"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
filter_path="${CLAUDE_STATUSLINE_JQ:-$script_dir/claude-statusline.jq}"

exec jq -r --arg branch "$branch" --arg profile "$profile" -f "$filter_path"
