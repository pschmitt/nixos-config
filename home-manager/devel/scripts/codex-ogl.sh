#!/usr/bin/env bash
# Run Codex behind og-local and Secretgate (see ogl-secretgate) while keeping
# the managed Codex config.
#
# `ogl codex` points CODEX_HOME at a bare directory of its own (a config.toml
# with just the proxy provider, plus a copy of auth.json), so hooks, skills,
# MCP servers, AGENTS.md and the model choice would be lost. ogl starts this
# script again as the "codex" binary (OGL_CODEX_BIN); the second run rebuilds
# that directory from the real Codex home: the real config plus ogl's provider,
# everything else symlinked.

if [[ -z "${CODEX_OGL_REAL_HOME:-}" ]]
then
  # first run: hand over to ogl, remembering where the real config lives
  CODEX_OGL_REAL_HOME="${CODEX_HOME:-$HOME/.codex}"
  OGL_CODEX_BIN="$(readlink -f "$0")"
  export CODEX_OGL_REAL_HOME OGL_CODEX_BIN
  exec ogl-secretgate codex "$@"
fi

real_home="$CODEX_OGL_REAL_HOME"
ogl_home="$CODEX_HOME"
ogl_config="$ogl_home/config.toml"
merged="$(mktemp "$ogl_home/config.toml.XXXXXX")"

# ogl's config is top-level keys followed by tables; ours is the same. Keep
# ogl's keys first (it selects its profile), then ours without a profile of
# its own, then ogl's tables.
{
  awk '/^\[/ { exit } { print }' "$ogl_config"
  grep -Ev '^profile[[:space:]]*=' "$real_home/config.toml"
  echo
  awk 'found || /^\[/ { found = 1; print }' "$ogl_config"
} > "$merged"
mv "$merged" "$ogl_config"

# Share everything else (skills, sessions, history, databases, ...) with the
# real home. auth.json is linked too so token refreshes land in the real one.
shopt -s dotglob nullglob
for entry in "$real_home"/*
do
  name="$(basename "$entry")"
  case "$name" in
    config.toml|ogl) continue ;;
  esac
  ln -sfn "$entry" "$ogl_home/$name"
done

exec codex "$@"
