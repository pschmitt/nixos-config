#!/usr/bin/env bash
set -euo pipefail

GEMINI_DIR="$HOME/.gemini/antigravity-cli"
BRAIN_DIR="$GEMINI_DIR/brain"
BEFORE_SESSIONS=""

record_sessions() {
  if [[ -d "$BRAIN_DIR" ]]; then
    find "$BRAIN_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
  fi
}

cleanup_new_sessions() {
  local before_file="$1"
  local after_file
  after_file="$(mktemp)"

  record_sessions > "$after_file"

  comm -13 "$before_file" "$after_file" | while read -r session_id; do
    if [[ -n "$session_id" ]]; then
      printf 'agy-warmup: cleaning up throwaway session %s\n' "$session_id"
      rm -rf "${BRAIN_DIR:?}/${session_id:?}"
      rm -f "${GEMINI_DIR:?}/conversations/${session_id:?}.db" \
            "${GEMINI_DIR:?}/annotations/${session_id:?}.pbtxt" \
            "${GEMINI_DIR:?}/presence/${session_id:?}.lock"
    fi
  done

  rm -f "$before_file" "$after_file"
}

cleanup() {
  if [[ -n "$BEFORE_SESSIONS" && -f "$BEFORE_SESSIONS" ]]; then
    cleanup_new_sessions "$BEFORE_SESSIONS"
  fi
}

main() {
  trap cleanup EXIT

  BEFORE_SESSIONS="$(mktemp)"
  record_sessions > "$BEFORE_SESSIONS"

  printf '=== agy-warmup: warming up Gemini models ===\n'
  agy --model gemini-3.8-flash-high -p "Say 'hi' and just 'hi'." || true

  printf '=== agy-warmup: warming up Claude & GPT models ===\n'
  agy --model claude-sonnet-4-6 -p "Say 'hi' and just 'hi'." || true

  printf '=== agy-warmup: checking quota ===\n'
  agy -p "/usage"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
