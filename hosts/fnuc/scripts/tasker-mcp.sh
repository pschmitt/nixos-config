#!/usr/bin/env bash

export TASKER_ADB_SERIAL
TASKER_ADB_SERIAL=$(<"${TASKER_MCP_CONFIG_DIR}/adb-serial")
export TASKER_TOKEN_FILE="${TASKER_MCP_CONFIG_DIR}/token"

# tasker-mcp always forwards local port 1821, so a second phone needs its own
# local port: forward it here and hand tasker-mcp the URL.
if [[ -n ${TASKER_MCP_LOCAL_PORT:-} ]]
then
  adb -s "$TASKER_ADB_SERIAL" forward "tcp:${TASKER_MCP_LOCAL_PORT}" tcp:1821 >/dev/null
  export TASKER_URL="http://localhost:${TASKER_MCP_LOCAL_PORT}"
fi
unset TASKER_WRITE_ALLOW TASKER_WRITE_ALLOW_PROJECTS
export TASKER_ALLOW_CONFIG_IMPORT=true
exec tasker-mcp "$@"
