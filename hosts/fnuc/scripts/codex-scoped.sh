#!/usr/bin/env bash
# Run codex (and everything it spawns: MCP servers, shells, builds) in its
# own transient systemd scope with memory caps, so a runaway session gets
# throttled or OOM-killed on its own instead of pushing all of user.slice
# into MemoryHigh reclaim and swap thrash.
# Expects CODEX_REAL (the unwrapped binary) and CODEX_SCOPE_PROPERTIES
# (space-separated systemd properties) from the wrapper environment.

can_scope() {
  # Already scoped (nested codex), explicitly disabled, or no user manager
  # to talk to (e.g. a PAM-less rescue shell): run codex directly.
  [[ -z "${CODEX_SCOPED:-}" ]] &&
    [[ -z "${CODEX_NO_SCOPE:-}" ]] &&
    [[ -S "${XDG_RUNTIME_DIR:-/run/user/${UID}}/bus" ]]
}

main() {
  local -a props
  local prop

  if ! can_scope
  then
    exec "$CODEX_REAL" "$@"
  fi

  read -r -a props <<< "$CODEX_SCOPE_PROPERTIES"

  local -a args=(--user --scope --quiet --collect --same-dir --unit "codex-$$")
  for prop in "${props[@]}"
  do
    args+=(--property "$prop")
  done

  export CODEX_SCOPED=1
  exec systemd-run "${args[@]}" -- "$CODEX_REAL" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
