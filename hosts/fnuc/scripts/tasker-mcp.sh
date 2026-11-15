#!/usr/bin/env bash

export TASKER_ADB_SERIAL
TASKER_ADB_SERIAL=$(<"${TASKER_MCP_CONFIG_DIR}/adb-serial")
export TASKER_TOKEN_FILE="${TASKER_MCP_CONFIG_DIR}/token"
export TASKER_WRITE_ALLOW="TaskerMCP.Test,TaskerMCP."
exec tasker-mcp "$@"
