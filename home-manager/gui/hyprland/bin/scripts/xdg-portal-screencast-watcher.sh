#!/usr/bin/env bash
# Monitor D-Bus for XDG Portals screencasting events
# Requires: busctl and jq

echo_debug() {
  if  [[ -z "$DEBUG" ]]
  then
    return 0
  fi

  echo -e "\e[1;30mDBG \e[0m$*"
}

echo_info() {
  echo -e "\e[1;34mINF \e[0m$*"
}

echo_error() {
  echo -e "\e[1;31mERR \e[0m$*"
}

echo_warning() {
  echo -e "\e[1;33mWRN \e[0m$*"
}

process_screencast_msg() {
  local interface="$1"
  local type="$2"
  local member="$3"

  echo_debug "$interface $type $member"

  if [[ "$type" == "method_call" && "$member" == "Start" ]]
  then
    echo_info "Screencasting started"
    if [[ -z "$NO_CALLBACK" ]]
    then
      ~/.config/hypr/bin/screencast.sh on &
    fi
    return 0
  fi
}

process_session_msg() {
  local interface="$1"
  local type="$2"
  local member="$3"

  echo_debug "$interface $type $member"

  if [[ "$type" == "method_call" && "$member" == "Close" ]]
  then
    echo_info "Screencasting stopped"
    if [[ -z "$NO_CALLBACK" ]]
    then
      ~/.config/hypr/bin/screencast.sh off &
    fi
    return 0
  fi
}

busctl monitor --user --json=short |
while read -r LINE
do
  IFS='	' read -r INTERFACE TYPE MEMBER <<<"$(jq -r '.interface + "\t" + .type + "\t" + .member' <<< "$LINE")"

  if [[ "$INTERFACE" == "org.freedesktop.portal.ScreenCast" ]]
  then
    echo_debug "$LINE"
    process_screencast_msg "$INTERFACE" "$TYPE" "$MEMBER"
  elif [[ "$INTERFACE" == "org.freedesktop.impl.portal.Session" ]]
  then
    echo_debug "$LINE"
    process_session_msg "$INTERFACE" "$TYPE" "$MEMBER"
  fi
done
