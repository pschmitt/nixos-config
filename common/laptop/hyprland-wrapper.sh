#!/usr/bin/env bash

# Hyprland already sets some env vars itself on startup:
# - HYPRLAND_CMD
# - XDG_BACKEND
# - _JAVA_AWT_WM_NONREPARENTING
# - MOZ_ENABLE_WAYLAND
# - XDG_CURRENT_DESKTOP
# https://github.com/hyprwm/Hyprland/blob/main/src/main.cpp#L32-L36
export XDG_BACKEND=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_CLASS=user
export XDG_SESSION_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

export HYPRLAND_SESSION_WRAPPER="$0"

# NOTE Below will result in an error shown on startup
# Failed to start graphical-session.target: Operation refused, unit graphical-sion.target may be requested by dependency only (it is configured to refuse mal start/stop). See user logs and systemctl -uur status graphical-sesion,target for details.
# systemctl --user start graphical-session.target
# trap "systemctl --user stop graphical-session.target" EXIT INT TERM

GTK_THEME=$($HOME/bin/zhj theme::current)
export GTK_THEME

systemd-run --user --scope --collect --quiet --unit="hyprland" \
  systemd-cat --identifier="hyprland" Hyprland "$@"
