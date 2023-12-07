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

PATH="$("$HOME/bin/zhj" path::export --value-only)"
export PATH

GTK_THEME="$("$HOME/bin/zhj" theme::current)"
export GTK_THEME

# Set XDG_CACHE_HOME so that crash reports land in there
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"

# FIXME Below has strange effects. Hyprland often does not start at all and has some serious trouble when exiting
# exec systemd-run --user --scope --collect --quiet --unit="hyprland" \
#   systemd-cat --identifier="hyprland" Hyprland

systemd-cat --identifier="hyprland" Hyprland
