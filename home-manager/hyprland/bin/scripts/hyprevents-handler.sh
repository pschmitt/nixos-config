#!/usr/bin/env bash

# default handlers for hyprevents
#
# override the function in your own events
# file to provide a custom handler
#
# comments inside each handler list the variables
# that are set when the handler is invoked

STATE_DIR="${XDG_RUNTIME_DIR}/hypr/hyprevents"
WS_CURRENT_FILE="${STATE_DIR}/current-workspace"
WS_PREV_FILE="${STATE_DIR}/previous-workspace"

event_activelayout() {
  : # KEYBOARDNAME LAYOUTNAME
}

event_activewindow() {
  : # WINDOWCLASS WINDOWTITLE
}

event_activewindowv2() {
  : # WINDOWADDRESS
}

event_closelayer() {
  : # NAMESPACE
}

event_closewindow() {
  : # WINDOWADDRESS
}

event_configreloaded() {
  : #
}

event_createworkspace() {
  : # WORKSPACENAME
}

event_destroyworkspace() {
  : # WORKSPACENAME
}

event_focusedmon() {
  : # MONNAME WORKSPACENAME
}

event_fullscreen() {
  : # ENTER (0 if leaving fullscreen, 1 if entering)
}

event_monitoradded() {
  : # MONITORNAME
}

event_monitorremoved() {
  : # MONITORNAME
}

event_movewindow() {
  : # WINDOWADDRESS WORKSPACENAME
}

event_moveworkspace() {
  : # WORKSPACENAME MONNAME
}

event_openlayer() {
  : # NAMESPACE
}

event_openwindow() {
  : # WINDOWADDRESS WORKSPACENAME WINDOWCLASS WINDOWTITLE
}

event_screencast() {
  echo "SCREENCAST EVENT: STATE=$STATE OWNER=$OWNER" >&2
  : # STATE OWNER
}

event_submap() {
  : # SUBMAPNAME
}

event_urgent() {
  : # WINDOWADDRESS
}

event_windowtitle() {
  : # WINDOWADDRESS
}

event_workspace() {
  echo "WORKSPACE CHANGED: $WORKSPACENAME" >&2

  mkdir -p "$STATE_DIR"

  # Store previous and current workspaces
  local previous_workspace
  previous_workspace=$(cat "$WS_CURRENT_FILE" 2>/dev/null)
  if [[ -n "$previous_workspace" ]]
  then
    echo "$previous_workspace" > "$WS_PREV_FILE"
  fi

  echo "$WORKSPACENAME" > "$WS_CURRENT_FILE"
}
