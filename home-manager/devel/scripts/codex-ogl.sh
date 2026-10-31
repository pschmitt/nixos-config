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

# ogl writes the legacy form (`profile = "ogl"` plus a [profiles.ogl] table),
# which current Codex rejects. Keep only its [model_providers.ogl] table, merge
# it into our real config, and select it with a profile file instead:
# `--profile ogl` reads ogl.config.toml from CODEX_HOME.
{
  grep -Ev '^profile[[:space:]]*=' "$real_home/config.toml"
  echo
  awk '/^\[/ { want = ($0 == "[model_providers.ogl]") } want { print }' "$ogl_config"
} > "$merged"
mv "$merged" "$ogl_config"
printf 'model_provider = "ogl"\n' > "$ogl_home/ogl.config.toml"

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

exec codex --profile ogl "$@"
