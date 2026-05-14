{ lib, ... }:
let
  luaBind = import ../lib/lua-bind.nix { inherit lib; };

  mod = "SUPER";
  binDir = "~/.config/hypr/bin";
  swayBinDir = "~/.config/sway/bin";
  barify = "${swayBinDir}/barify";
  brightnessUp = "${barify} brightness up";
  brightnessDown = "${barify} brightness down";
  volumeSinkUp = "${barify} sink up";
  volumeSinkDown = "${barify} sink down";
  volumeSinkMute = "${barify} sink mute";
  playerctlToggle = "${swayBinDir}/playerctl-wrapper.sh toggle";
  playerctlPause = "${swayBinDir}/playerctl-wrapper.sh pause";
  playerctlNext = "${swayBinDir}/playerctl-wrapper.sh next";
  playerctlPrevious = "${swayBinDir}/playerctl-wrapper.sh previous";
  mouseSubmap = "🖱️ mouse";
  resizeSubmap = "↔️ resize";

  hyprBinds = [
    "${mod} SHIFT, C, killactive,"
    "${mod} SHIFT, K, exec, hyprctl kill"
    "${mod} SHIFT, Q, exec, ${binDir}/leave.sh"
    "${mod} SHIFT, R, exec, ${binDir}/reload-config.sh"
  ];

  tilingBinds = [
    "${mod} SHIFT, space, togglefloating,"
    "${mod} ALT, space, layoutmsg, togglesplit"
    "${mod}, minus, layoutmsg, togglesplit"
    "${mod}, P, pseudo,"
    "${mod} SHIFT, comma, exec, ${binDir}/switch-layout.sh"
    "${mod}, T, togglegroup"
    "${mod} SHIFT, T, moveoutofgroup"
    "${mod}, comma, changegroupactive"
  ];

  workspaceScrollBinds = [
    "${mod}, mouse_down, workspace, e+1"
    "${mod}, mouse_up, workspace, e-1"
  ];

  mouseMoveResizeBinds = [
    "${mod}, mouse:272, movewindow"
    "${mod}, mouse:273, resizewindow"
  ];

  fullscreenBinds = [
    "${mod}, F, fullscreen,"
    "${mod}, M, fullscreen, 1"
    "${mod} SHIFT, F, fullscreenstate, -1, 2"
  ];

  windowMoveExecBinds = [
    "${mod}, left, exec, ${binDir}/move-window.sh l"
    "${mod}, right, exec, ${binDir}/move-window.sh r"
    "${mod}, up, exec, ${binDir}/move-window.sh u"
    "${mod}, down, exec, ${binDir}/move-window.sh d"
    "${mod}, s, swapnext,"
    "${mod} SHIFT, up, movewindow, mon:+1"
    "${mod} SHIFT, up, focusmonitor, +1"
    "${mod} SHIFT, up, movecursortocorner, 4"
    "${mod} SHIFT, down, movewindow, mon:-1"
    "${mod} SHIFT, down, focusmonitor, -1"
    "${mod} SHIFT, down, movecursortocorner, 3"
    "${mod} SHIFT, left, movetoworkspacesilent, -1"
    "${mod} SHIFT, right, movetoworkspacesilent, +1"
  ];

  focusBinds = [
    "${mod}, h, movefocus, l"
    "${mod}, l, movefocus, r"
    "${mod}, k, movefocus, u"
    "${mod}, j, movefocus, d"
    "${mod} SHIFT, tab, exec, ${binDir}/switch-workspace.sh previous"
    "${mod} ALT, left, workspace, -1"
    "${mod} ALT, right, workspace, +1"
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
      "${mod}, ${entry.key}, workspace, ${entry.workspace}"
    ]) workspaceKeys
  );

  workspaceMoveBinds = map (
    entry: "${mod} SHIFT, ${entry.key}, movetoworkspace, ${entry.workspace}"
  ) workspaceKeys;

  globalBinde = [
    "${mod} SHIFT, h, resizeactive, -25 0"
    "${mod} SHIFT, j, resizeactive, 0 25"
    "${mod} SHIFT, k, resizeactive, 0 -25"
    "${mod} SHIFT, l, resizeactive, 25 0"
  ];

  appBinds = [
    ", Print, exec, ${binDir}/screenshot.sh"
    "${mod}, Return, exec, ${binDir}/term.sh"
    "${mod} SHIFT, Return, exec, ${binDir}/term.sh"
    "${mod}, W, exec, ${binDir}/run-or-raise.sh firefox"
    "${mod} ALT, Y, exec, ${binDir}/browser-run-or-raise.sh --title youtube --url https://www.youtube.com"
    "${mod} ALT, Z, exec, ${binDir}/ms-teams-join-room.sh home-room"
    "${mod} ALT, T, exec, ${binDir}/ms-teams-join-room.sh home-room"
    "${mod} SHIFT, Z, exec, zhj 'hyprctl::bring-window --fullscreen chrome'"
    "${mod} ALT, H, exec, ${binDir}/browser-run-or-raise.sh --url https://ha.brkn.lol --alt http://10.5.1.1:8123"
    # the '#' key
    "${mod} ALT, numbersign, exec, ${binDir}/browser-rbw.sh"
    ", F1, exec, ${binDir}/scratchpad.sh term"
    "${mod}, E, exec, ${binDir}/scratchpad.sh files"
    "${mod} SHIFT, V, exec, ${binDir}/scratchpad.sh audio"
    "${mod} ALT, a, exec, ~/bin/obs.zsh alt"
    "${mod} ALT, w, exec, ~/bin/obs.zsh webcam"
    "${mod} ALT, f, exec, ~/bin/obs.zsh freeze"
    "${mod} ALT, up, exec, ~/bin/obs.zsh thumbs-up"
    "${mod} ALT, down, exec, ~/bin/obs.zsh thumbs-down"
    "${mod} ALT, period, exec, ~/bin/obs.zsh emoji"
    "${mod}, R, exec, ~/bin/wofi.zsh run"
    "${mod}, period, exec, ~/bin/wofi.zsh emoji"
    "${mod} ALT, c, exec, ~/.config/waybar/custom_modules/clipboard.sh"
    "${mod} ALT, v, exec, zhj clipboard::revert --notify"
    "${mod} ALT, p, exec, ~/bin/wofi.zsh bitwarden"
    "${mod} ALT, m, exec, ~/bin/wofi.zsh misc"
    "${mod} ALT, j, exec, ~/bin/wofi.zsh meetings"
    "${mod} ALT, g, exec, ~/bin/wofi.zsh bitwarden-work"
    "${mod} ALT, s, exec, ~/bin/wofi.zsh soundboard"
    "${mod} SHIFT, s, exec, ~/bin/wofi.zsh soundboard stop"
  ];

  mouseModeBinds = [
    "${mod} SHIFT, M, submap, ${mouseSubmap}"
    "${mod}, numbersign, exec, waypoint"
    "${mod} SHIFT, H, exec, killall hints; hints"
  ];

  resizeModeBind = [ "${mod} ALT, R, submap, ${resizeSubmap}" ];

  brightnessBinds = [
    ", XF86MonBrightnessUp, exec, ${brightnessUp}"
    ", XF86MonBrightnessDown, exec, ${brightnessDown}"
  ];

  audioBinds = [
    ", XF86AudioRaiseVolume, exec, ${volumeSinkUp}"
    ", XF86AudioLowerVolume, exec, ${volumeSinkDown}"
    ", XF86AudioMute, exec, ${volumeSinkMute}"
    ", XF86AudioMicMute, exec, ~/bin/obs.zsh toggle-mute"
    "${mod}, space, exec, ~/bin/obs.zsh toggle-mute"
  ];

  playerctlBinds = [
    ", XF86AudioPlay, exec, ${playerctlToggle}"
    ", XF86AudioPause, exec, ${playerctlPause}"
    ", XF86AudioNext, exec, ${playerctlNext}"
    ", XF86AudioPrev, exec, ${playerctlPrevious}"
    "CONTROL ALT, up, exec, ${playerctlToggle}"
    "CONTROL ALT, right, exec, ${playerctlNext}"
    "CONTROL ALT, left, exec, ${playerctlPrevious}"
  ];

  obsBindl = [ "${mod} ALT, b, exec, ~/bin/obs.zsh brb --mute" ];
in
{
  wayland.windowManager.hyprland = {
    settings = lib.mkMerge [
      {
        bind =
          (map luaBind.mkBind (
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
            ++ appBinds
          ))
          ++ (map (
            row: (luaBind.mkBind row) // { _args = (luaBind.mkBind row)._args ++ [ { mouse = true; } ]; }
          ) mouseMoveResizeBinds)
          ++ (map luaBind.mkRepeatingBind globalBinde)
          ++ (map luaBind.mkLockedBind (brightnessBinds ++ audioBinds ++ playerctlBinds ++ obsBindl));
      }
    ];

    submaps = {
      "${mouseSubmap}".settings = {
        bind = [
          (luaBind.mkLuaBind "right" (luaBind.execCmd "zhj mouse::move +25") { repeating = true; })
          (luaBind.mkLuaBind "left" (luaBind.execCmd "zhj mouse::move -25") { repeating = true; })
          (luaBind.mkLuaBind "up" (luaBind.execCmd "zhj mouse::move -y -25") { repeating = true; })
          (luaBind.mkLuaBind "down" (luaBind.execCmd "zhj mouse::move -y +25") { repeating = true; })
          (luaBind.mkLuaBind "SHIFT + right" (luaBind.execCmd "zhj mouse::move +50") { repeating = true; })
          (luaBind.mkLuaBind "SHIFT + left" (luaBind.execCmd "zhj mouse::move -50") { repeating = true; })
          (luaBind.mkLuaBind "SHIFT + up" (luaBind.execCmd "zhj mouse::move -y -50") { repeating = true; })
          (luaBind.mkLuaBind "SHIFT + down" (luaBind.execCmd "zhj mouse::move -y +50") { repeating = true; })
          (luaBind.mkLuaBind "ALT + right" (luaBind.execCmd "zhj mouse::move +5") { repeating = true; })
          (luaBind.mkLuaBind "ALT + left" (luaBind.execCmd "zhj mouse::move -5") { repeating = true; })
          (luaBind.mkLuaBind "ALT + up" (luaBind.execCmd "zhj mouse::move -y -5") { repeating = true; })
          (luaBind.mkLuaBind "ALT + down" (luaBind.execCmd "zhj mouse::move -y +5") { repeating = true; })
          {
            _args = [
              "return"
              (luaBind.execCmd "zhj mouse::click")
            ];
          }
          {
            _args = [
              "space"
              (luaBind.execCmd "zhj mouse::click")
            ];
          }
          {
            _args = [
              "SHIFT + return"
              (luaBind.execCmd "zhj mouse::click right")
            ];
          }
          {
            _args = [
              "SHIFT + space"
              (luaBind.execCmd "zhj mouse::click right")
            ];
          }
          {
            _args = [
              "ALT + return"
              (luaBind.execCmd "zhj mouse::click middle")
            ];
          }
          {
            _args = [
              "ALT + space"
              (luaBind.execCmd "zhj mouse::click middle")
            ];
          }
          (luaBind.mkLuaBind "SHIFT + 0" (luaBind.execCmd "dotoolc <<< 'mouseto 0 0'") { repeating = true; })
          (luaBind.mkLuaBind "SHIFT + 1" (luaBind.execCmd "dotoolc <<< 'mouseto 1 0'") { repeating = true; })
          (luaBind.mkLuaBind "SHIFT + 2" (luaBind.execCmd "dotoolc <<< 'mouseto 1 1'") { repeating = true; })
          (luaBind.mkLuaBind "SHIFT + 3" (luaBind.execCmd "dotoolc <<< 'mouseto 0 1'") { repeating = true; })
          (luaBind.mkLuaBind "0" (luaBind.execCmd "dotoolc <<< 'mouseto 0.25 0.25'") { repeating = true; })
          (luaBind.mkLuaBind "1" (luaBind.execCmd "dotoolc <<< 'mouseto 0.75 0.25'") { repeating = true; })
          (luaBind.mkLuaBind "2" (luaBind.execCmd "dotoolc <<< 'mouseto 0.75 0.75'") { repeating = true; })
          (luaBind.mkLuaBind "3" (luaBind.execCmd "dotoolc <<< 'mouseto 0.25 0.75'") { repeating = true; })
          (luaBind.mkLuaBind "${mod} + SHIFT + space" (luaBind.execCmd "dotoolc <<< 'buttondown left'") {
            repeating = true;
          })
          (luaBind.mkLuaBind "${mod} + SHIFT + return" (luaBind.execCmd "dotoolc <<< 'buttondown left'") {
            repeating = true;
          })
          (luaBind.mkLuaBind "${mod} + space" (luaBind.execCmd "dotoolc <<< 'buttonup left'") {
            repeating = true;
          })
          (luaBind.mkLuaBind "${mod} + return" (luaBind.execCmd "dotoolc <<< 'buttonup left'") {
            repeating = true;
          })
          {
            _args = [
              "escape"
              (luaBind.submapTo "reset")
            ];
          }
          {
            _args = [
              "q"
              (luaBind.submapTo "reset")
            ];
          }
        ];
      };

      "${resizeSubmap}".settings = {
        bind = [
          {
            _args = [
              "escape"
              (luaBind.submapTo "reset")
            ];
          }
          {
            _args = [
              "return"
              (luaBind.submapTo "reset")
            ];
          }
          (luaBind.mkLuaBind "right" (luaBind.resizeActive 25 0) { repeating = true; })
          (luaBind.mkLuaBind "left" (luaBind.resizeActive (-25) 0) { repeating = true; })
          (luaBind.mkLuaBind "up" (luaBind.resizeActive 0 (-25)) { repeating = true; })
          (luaBind.mkLuaBind "down" (luaBind.resizeActive 0 25) { repeating = true; })
        ];
      };
    };
  };
}
