#!/usr/bin/env bash

main() {
  local event_name
  event_name=$(jq -r '.hook_event_name // empty' 2>/dev/null || true)

  if [[ -z "$event_name" ]]
  then
    printf 'Missing hook_event_name in hook input\n' >&2
    return 1
  fi

  local additional_context
  additional_context=""

  if [[ -n "${TMUX_PANE:-}" ]] && tmux display-message -p -t "$TMUX_PANE" '#{pane_id}' >/dev/null 2>&1
  then
    additional_context="This agent is running in tmux pane ${TMUX_PANE}. Before doing task work, choose a concise window name that describes the user's current request and rename this pane's window with: tmux rename-window -t '${TMUX_PANE}' 'short-task-name'. Use this explicit pane target; never rename the active window by assumption."
  fi

  jq -cn \
    --arg event_name "$event_name" \
    --arg additional_context "$additional_context" \
    '{hookSpecificOutput: {hookEventName: $event_name, additionalContext: $additional_context}}'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main
fi

# vim: set ft=sh et ts=2 sw=2 :
