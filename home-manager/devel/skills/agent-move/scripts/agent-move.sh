#!/usr/bin/env bash
# Copy a Claude Code or Codex session transcript to another host and resume
# it there in a tmux window.
#
# Usage: agent-move.sh [--agent claude|codex] [--dry-run] [--no-launch]
#                      SESSION_ID TARGET_HOST
set -euo pipefail

agent=claude
dry_run=0
launch=1

while [[ $# -gt 0 ]]
do
  case "$1" in
    --agent) agent="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --no-launch) launch=0; shift ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

if [[ $# -ne 2 ]]
then
  echo "Usage: ${0##*/} [--agent claude|codex] [--dry-run] [--no-launch] SESSION_ID TARGET_HOST" >&2
  exit 2
fi

session="$1"
target="$2"

if [[ "$target" == "$(hostname)" ]]
then
  echo "Refusing to move a session to the host it is already on." >&2
  exit 1
fi

run() {
  if [[ "$dry_run" == 1 ]]
  then
    printf '+ %q ' "$@"
    echo
  else
    "$@"
  fi
}

case "$agent" in
  claude)
    root="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"
    transcript="$(compgen -G "$root/projects/*/$session.jsonl" | head -n1 || true)"
    ;;
  codex)
    root="${CODEX_HOME:-$HOME/.codex}"
    transcript="$(compgen -G "$root/sessions/*/*/*/rollout-*-$session.jsonl" | head -n1 || true)"
    ;;
  *)
    echo "Unknown agent: $agent" >&2
    exit 2
    ;;
esac

if [[ -z "$transcript" ]]
then
  echo "No $agent transcript found for session $session under $root" >&2
  exit 1
fi

cwd="$(jq -r 'select(.cwd != null) | .cwd' "$transcript" | head -n1)"
if [[ -z "$cwd" ]]
then
  echo "Could not determine the session's working directory" >&2
  exit 1
fi

echo "Transcript: $transcript"
echo "Working dir: $cwd"

# The cwd must exist on the target, otherwise --resume cannot find the project.
if ! ssh "$target" test -d "$cwd"
then
  echo "Target $target has no $cwd. Clone or sync the repository first." >&2
  exit 1
fi

# Warn about uncommitted work: the transcript does not carry the files.
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1
then
  if [[ -n "$(git -C "$cwd" status --porcelain)" ]]
  then
    echo "WARNING: $cwd has uncommitted changes on this host; they are NOT moved." >&2
    echo "         Commit/push them (or rsync the tree) before resuming on $target." >&2
  fi
  echo "Local HEAD: $(git -C "$cwd" rev-parse --short HEAD) ($(git -C "$cwd" rev-parse --abbrev-ref HEAD))"
fi

# Transcript plus the per-session directory (subagents, tool results).
rel="${transcript#"$root"/}"
run ssh "$target" mkdir -p "$root/$(dirname "$rel")"
run rsync -a "$transcript" "$target:$root/$rel"

sessiondir="${transcript%.jsonl}"
if [[ "$agent" == claude && -d "$sessiondir" ]]
then
  run rsync -a "$sessiondir/" "$target:$root/${rel%.jsonl}/"
fi

if [[ "$launch" == 0 ]]
then
  echo "Copied. Resume on $target with: cd '$cwd' && $agent resume $session"
  exit 0
fi

case "$agent" in
  claude) resume_cmd="claude --resume $session" ;;
  codex) resume_cmd="codex resume $session" ;;
esac

run ssh "$target" \
  "tmux new-window -c '$cwd' -n 'moved-${session:0:8}' '$resume_cmd'"
echo "Resumed on $target in a new tmux window (moved-${session:0:8})."
