#!/usr/bin/env bash
# Run a coding agent behind both secret filters: og-local (ML detector for
# PII, passwords and shapeless secrets) and Secretgate (regexes for key and
# token formats, which og-local misses).
#
#   agent -> ogl (placeholders) -> secretgate (TLS intercept, regexes) -> provider
#
# Usage: ogl-secretgate AGENT [ARGS...]   (AGENT: claude or codex)
# OGL_SECRETGATE_MODE: off (default), redact, block or audit.
#
# Secretgate is off by default: with it in the chain, turns that call a tool
# (any MCP tool) hang after the first model response, in audit mode too.
# og-local alone handles tool calls. Enable it once that is fixed.

free_port() {
  local port
  while true
  do
    port="$(shuf -i 20000-60000 -n 1)"
    if ! ss -Htln "sport = :${port}" | grep -q .
    then
      echo "$port"
      return 0
    fi
  done
}

main() {
  local mode="${OGL_SECRETGATE_MODE:-off}"
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/secretgate"
  local reverse_port forward_port

  if [[ "$mode" == off ]]
  then
    exec ogl "$@"
  fi

  mkdir -p "$state_dir"
  reverse_port="$(free_port)"
  forward_port="$(free_port)"

  exec secretgate wrap --no-harden \
    --mode "$mode" \
    --port "$reverse_port" \
    --forward-proxy-port "$forward_port" \
    --log-file "$state_dir/wrap.log" \
    -- ogl "$@"
}

main "$@"
