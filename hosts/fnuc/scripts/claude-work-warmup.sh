#!/usr/bin/env bash

SESSION="claude-work-warmup"
LOAD_TIMEOUT="${LOAD_TIMEOUT:-30}"
RESPONSE_WAIT="${RESPONSE_WAIT:-60}"

# Polls the pane until its content stops changing between two 1s samples,
# which is how we detect that the claude-work TUI has finished loading
# without hardcoding a fixed startup delay.
wait_for_stable_pane() {
  local target="$1"
  local timeout="$2"
  local prev="" cur="" waited=0

  while (( waited < timeout ))
  do
    cur="$(tmux capture-pane -p -t "$target")"
    if [[ -n "$cur" && "$cur" == "$prev" ]]
    then
      return 0
    fi
    prev="$cur"
    sleep 1
    waited=$(( waited + 1 ))
  done

  return 1
}

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || :
}

dump_pane() {
  local label="$1"

  printf '=== claude-work-warmup: %s ===\n' "$label"
  tmux capture-pane -p -S -200 -t "$SESSION"
}

main() {
  trap cleanup EXIT

  # Clean up any leftover session from a previous crashed run.
  tmux kill-session -t "$SESSION" 2>/dev/null || :

  tmux new-session -d -s "$SESSION" -x 250 -y 50 "$CLAUDE_WORK_WARMUP_LAUNCH"

  if wait_for_stable_pane "$SESSION" "$LOAD_TIMEOUT"
  then
    printf 'claude-work-warmup: pane stabilized (loaded)\n'
  else
    printf 'claude-work-warmup: pane did not stabilize within %ss, continuing anyway\n' \
      "$LOAD_TIMEOUT" >&2
  fi
  dump_pane "pane after load, before greeting"

  tmux send-keys -t "$SESSION" "Say 'hi' and just 'hi'." Enter

  # Give claude-work a moment to start rendering (spinner etc.) before we
  # start debouncing, so a still-idle first sample doesn't read as "done".
  sleep 2
  if wait_for_stable_pane "$SESSION" "$RESPONSE_WAIT"
  then
    printf 'claude-work-warmup: pane stabilized after greeting (response received)\n'
  else
    printf 'claude-work-warmup: pane did not stabilize within %ss after greeting, no response detected\n' \
      "$RESPONSE_WAIT" >&2
  fi
  dump_pane "pane after greeting response wait"

  tmux send-keys -t "$SESSION" "/usage" Enter
  sleep 5
  dump_pane "pane after /usage"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
