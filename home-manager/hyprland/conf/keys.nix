{ lib, ... }:
let
  mouseSubmap = "🖱️ mouse";
  resizeSubmap = "↔️ resize";

  hyprBinds = [
    # Core Hyprland management helpers.
    "$mod SHIFT, C, exec, $bin_dir/kill-active.sh"
    "$mod SHIFT, K, exec, hyprctl kill"
    "$mod SHIFT, Q, exec, $bin_dir/leave.sh"
    "$mod SHIFT, R, exec, $bin_dir/reload-config.sh"
  ];

  tilingBinds = [
    # Tiling / layout controls.
    "$mod SHIFT, space, togglefloating,"
    "$mod ALT, space, togglesplit,"
    "$mod, minus, togglesplit,"
    "$mod, P, pseudo,"
    "$mod SHIFT, comma, exec, $bin_dir/switch-layout.sh"
    "$mod, T, togglegroup"
    "$mod SHIFT, T, moveoutofgroup"
    "$mod, comma, changegroupactive"
  ];

  workspaceScrollBinds = [
    # Scroll through workspaces with mod + mouse wheel.
    "$mod, mouse_down, workspace, e+1"
    "$mod, mouse_up, workspace, e-1"
  ];

  mouseMoveResizeBinds = [
    # Drag to move/resize with the mouse.
    "$mod, mouse:272, movewindow"
    "$mod, mouse:273, resizewindow"
  ];

  fullscreenBinds = [
    "$mod, F, fullscreen,"
    "$mod, M, fullscreen, 1"
    "$mod SHIFT, F, fullscreenstate, -1, 2"
  ];

  windowMoveExecBinds = [
    "$mod, left, exec, $bin_dir/move-window.sh l"
    "$mod, right, exec, $bin_dir/move-window.sh r"
    "$mod, up, exec, $bin_dir/move-window.sh u"
    "$mod, down, exec, $bin_dir/move-window.sh d"
    "$mod, s, swapnext,"
    "$mod SHIFT, up, movewindow, mon:+1"
    "$mod SHIFT, up, focusmonitor, +1"
    "$mod SHIFT, up, movecursortocorner, 4"
    "$mod SHIFT, down, movewindow, mon:-1"
    "$mod SHIFT, down, focusmonitor, -1"
    "$mod SHIFT, down, movecursortocorner, 3"
    "$mod SHIFT, left, movetoworkspacesilent, -1"
    "$mod SHIFT, right, movetoworkspacesilent, +1"
  ];

  focusBinds = [
    "$mod, h, movefocus, l"
    "$mod, l, movefocus, r"
    "$mod, k, movefocus, u"
    "$mod, j, movefocus, d"
    "$mod SHIFT, tab, exec, $bin_dir/switch-workspace.sh previous"
    "$mod ALT, left, workspace, -1"
    "$mod ALT, right, workspace, +1"
  ];

  workspaceKeys = [
    {
      key = "1";
      workspace = "1";
    }
    {
      key = "2";
      workspace = "2";
    }
    {
      key = "3";
      workspace = "3";
    }
    {
      key = "4";
      workspace = "4";
    }
    {
      key = "5";
      workspace = "5";
    }
    {
      key = "6";
      workspace = "6";
    }
    {
      key = "7";
      workspace = "7";
    }
    {
      key = "8";
      workspace = "8";
    }
    {
      key = "9";
      workspace = "9";
    }
    {
      key = "0";
      workspace = "10";
    }
  ];

  workspaceNumberBinds = lib.flatten (
    map (entry: [
      "$mod, ${entry.key}, moveworkspacetomonitor, ${entry.workspace} current"
      "$mod, ${entry.key}, exec, $bin_dir/switch-workspace.sh ${entry.workspace}"
    ]) workspaceKeys
  );

  workspaceMoveBinds = map (
    entry: "$mod SHIFT, ${entry.key}, movetoworkspace, ${entry.workspace}"
  ) workspaceKeys;

  globalBinde = [
    "$mod SHIFT, h, resizeactive, -25 0"
    "$mod SHIFT, j, resizeactive, 0 25"
    "$mod SHIFT, k, resizeactive, 0 -25"
    "$mod SHIFT, l, resizeactive, 25 0"
  ];

  appBinds = [
    ", Print, exec, $bin_dir/screenshot.sh"
    "$mod, Return, exec, $bin_dir/term.sh"
    "$mod SHIFT, Return, exec, $bin_dir/term.sh"
    "$mod, W, exec, $bin_dir/run-or-raise.sh firefox"
    "$mod ALT, Y, exec, $bin_dir/browser-run-or-raise.sh --title youtube --url https://www.youtube.com"
    "$mod ALT, Z, exec, $bin_dir/ms-teams-join-room.sh home-room"
    "$mod ALT, T, exec, $bin_dir/ms-teams-join-room.sh home-room"
    "$mod SHIFT, Z, exec, zhj 'hyprctl::bring-window --fullscreen chrome'"
    "$mod ALT, H, exec, $bin_dir/browser-run-or-raise.sh --url https://hass.ovm5.de --alt http://10.5.1.1:8123"
    # the '#' key!
    "$mod ALT, numbersign, exec, $bin_dir/browser-rbw.sh"
    ", F1, exec, $bin_dir/scratchpad.sh term"
    "$mod, E, exec, $bin_dir/scratchpad.sh files"
    "$mod SHIFT, V, exec, $bin_dir/scratchpad.sh audio"
    "$mod ALT, a, exec, ~/bin/obs.zsh alt"
    "$mod ALT, w, exec, ~/bin/obs.zsh webcam"
    "$mod ALT, f, exec, ~/bin/obs.zsh freeze"
    "$mod ALT, up, exec, ~/bin/obs.zsh thumbs-up"
    "$mod ALT, down, exec, ~/bin/obs.zsh thumbs-down"
    "$mod ALT, period, exec, ~/bin/obs.zsh emoji"
    "$mod, R, exec, ~/bin/wofi.zsh run"
    "$mod, period, exec, ~/bin/wofi.zsh emoji"
    "$mod ALT, c, exec, ~/.config/waybar/custom_modules/clipboard.sh"
    "$mod ALT, v, exec, zhj clipboard::revert --notify"
    "$mod ALT, p, exec, ~/bin/wofi.zsh bitwarden"
    "$mod ALT, m, exec, ~/bin/wofi.zsh misc"
    "$mod ALT, j, exec, ~/bin/wofi.zsh meetings"
    "$mod ALT, g, exec, ~/bin/wofi.zsh bitwarden-work"
    "$mod ALT, s, exec, ~/bin/wofi.zsh soundboard"
    "$mod SHIFT, s, exec, ~/bin/wofi.zsh soundboard stop"
  ];

  mouseModeBinds = [
    "$mod SHIFT, M, submap, $submap_mouse"
    "$mod, numbersign, exec, waypoint"
    "$mod SHIFT, H, exec, killall hints; hints"
  ];

  resizeModeBind = [ "$mod ALT, R, submap, $submap_resize" ];

  brightnessBinds = [
    ", XF86MonBrightnessUp, exec, $brightness_up"
    ", XF86MonBrightnessDown, exec, $brightness_down"
  ];

  audioBinds = [
    ", XF86AudioRaiseVolume, exec, $volume_sink_up"
    ", XF86AudioLowerVolume, exec, $volume_sink_down"
    ", XF86AudioMute, exec, $volume_sink_mute"
    ", XF86AudioMicMute, exec, ~/bin/obs.zsh toggle-mute"
    "$mod, space, exec, ~/bin/obs.zsh toggle-mute"
  ];

  playerctlBinds = [
    ", XF86AudioPlay, exec, $playerctl_toggle"
    ", XF86AudioPause, exec, $playerctl_pause"
    ", XF86AudioNext, exec, $playerctl_next"
    ", XF86AudioPrev, exec, $playerctl_previous"
    "CONTROL ALT, up, exec, $playerctl_toggle"
    "CONTROL ALT, right, exec, $playerctl_next"
    "CONTROL ALT, left, exec, $playerctl_previous"
  ];

  obsBindl = [ "$mod ALT, b, exec, ~/bin/obs.zsh brb --mute" ];
in
{
  # Mirrors ~/.config/hypr/config.d/keys.conf (all binds/submaps).
  # Docs: https://wiki.hyprland.org/Configuring/Binds/.
  wayland.windowManager.hyprland = {
    settings = lib.mkMerge [
      {
        # Convenience variables from keys.conf.
        "$mod" = "SUPER";
        "$submap_mouse" = mouseSubmap;
        "$submap_resize" = resizeSubmap;
        "$barify" = "$sway_bin_dir/barify";
        "$brightness_up" = "$barify brightness up";
        "$brightness_down" = "$barify brightness down";
        "$volume_sink_up" = "$barify sink up";
        "$volume_sink_down" = "$barify sink down";
        "$volume_sink_mute" = "$barify sink mute";
        "$volume_source_up" = "$barify source up";
        "$volume_source_down" = "$barify source down";
        "$volume_source_mute" = "$barify source mute";
        "$playerctl_toggle" = "$sway_bin_dir/playerctl-wrapper.sh toggle";
        "$playerctl_play" = "$sway_bin_dir/playerctl-wrapper.sh play";
        "$playerctl_pause" = "$sway_bin_dir/playerctl-wrapper.sh pause";
        "$playerctl_next" = "$sway_bin_dir/playerctl-wrapper.sh next";
        "$playerctl_previous" = "$sway_bin_dir/playerctl-wrapper.sh previous";

        bind =
          hyprBinds
          ++ tilingBinds
          ++ workspaceScrollBinds
          ++ fullscreenBinds
          ++ windowMoveExecBinds
          ++ focusBinds
          ++ workspaceNumberBinds
          ++ workspaceMoveBinds
          ++ mouseModeBinds
          ++ resizeModeBind
          ++ appBinds;

        bindm = mouseMoveResizeBinds;

        binde = globalBinde;

        bindl = brightnessBinds ++ audioBinds ++ playerctlBinds ++ obsBindl;
      }
    ];

    submaps = {
      # Mouse helper submap from keys.conf.
      "${mouseSubmap}".settings = {
        binde = [
          ", right, exec, zhj mouse::move +25"
          ", left, exec, zhj mouse::move -25"
          ", up, exec, zhj mouse::move -y -25"
          ", down, exec, zhj mouse::move -y +25"
          "shift, right, exec, zhj mouse::move +50"
          "shift, left, exec, zhj mouse::move -50"
          "shift, up, exec, zhj mouse::move -y -50"
          "shift, down, exec, zhj mouse::move -y +50"
          "alt, right, exec, zhj mouse::move +5"
          "alt, left, exec, zhj mouse::move -5"
          "alt, up, exec, zhj mouse::move -y -5"
          "alt, down, exec, zhj mouse::move -y +5"
          ", return, exec, zhj mouse::click"
          ", space, exec, zhj mouse::click"
          "shift, return, exec, zhj mouse::click right"
          "shift, space, exec, zhj mouse::click right"
          "alt, return, exec, zhj mouse::click middle"
          "alt, space, exec, zhj mouse::click middle"
          "SHIFT, 0, exec, dotoolc <<< 'mouseto 0 0'"
          "SHIFT, 1, exec, dotoolc <<< 'mouseto 1 0'"
          "SHIFT, 2, exec, dotoolc <<< 'mouseto 1 1'"
          "SHIFT, 3, exec, dotoolc <<< 'mouseto 0 1'"
          ", 0, exec, dotoolc <<< 'mouseto 0.25 0.25'"
          ", 1, exec, dotoolc <<< 'mouseto 0.75 0.25'"
          ", 2, exec, dotoolc <<< 'mouseto 0.75 0.75'"
          ", 3, exec, dotoolc <<< 'mouseto 0.25 0.75'"
          "$mod SHIFT, space, exec, dotoolc <<< 'buttondown left'"
          "$mod SHIFT, return, exec, dotoolc <<< 'buttondown left'"
          "$mod, space, exec, dotoolc <<< 'buttonup left'"
          "$mod, return, exec, dotoolc <<< 'buttonup left'"
        ];
        bind = [
          ", escape, submap, reset"
          ", q, submap, reset"
        ];
      };

      # Resize helper submap.
      "${resizeSubmap}".settings = {
        binde = [
          ", right, resizeactive, 25 0"
          ", left, resizeactive, -25 0"
          ", up, resizeactive, 0 -25"
          ", down, resizeactive, 0 25"
        ];
        bind = [
          ", escape, submap, reset"
          ", return, submap, reset"
        ];
      };
    };
  };
}
