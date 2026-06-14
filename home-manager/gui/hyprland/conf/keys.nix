{ lib, ... }:
let
  h = import ../lua-helpers.nix { inherit lib; };
  inherit (h)
    bind
    bindOpts
    exec
    execBind
    execBindLocked
    ;

  bin = "~/.config/hypr/bin";
  swayBin = "~/.config/sway/bin";
  barify = "${swayBin}/barify";
  playerctl = "${swayBin}/playerctl-wrapper.sh";

  mouseSubmap = "🖱️ mouse";
  resizeSubmap = "↔️ resize";

  reset = combo: bind combo ''hl.dsp.submap("reset")'';

  # Workspace keys 1-10 (key "0" -> workspace 10).
  wsKeys = [
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
    "8"
    "9"
    "0"
  ];
  wsBinds = lib.concatMap (
    key:
    let
      ws = if key == "0" then 10 else lib.toInt key;
    in
    [
      (bind "SUPER + ${key}" ''hl.dsp.workspace.move({ workspace = ${toString ws}, monitor = "current" })'')
      (execBind "SUPER + ${key}" "${bin}/switch-workspace.sh ${toString ws}")
      (bind "SUPER + SHIFT + ${key}" "hl.dsp.window.move({ workspace = ${toString ws} })")
    ]
  ) wsKeys;

  # Mouse-mode submap helpers.
  mv = combo: args: bindOpts combo (exec "${bin}/mousectl.sh move ${args}") { repeating = true; };
  cl =
    combo: btn:
    execBind combo ("${bin}/mousectl.sh click" + lib.optionalString (btn != null) " ${btn}");
  mouseto =
    combo: x: y:
    execBind combo "dotoolc <<< 'mouseto ${x} ${y}'";
  mouseBtn = combo: action: execBind combo "dotoolc <<< 'button${action} left'";
in
{
  # Keybinds + submaps.
  # Docs: https://wiki.hypr.land/Configuring/Binds/
  wayland.windowManager.hyprland = {
    settings.bind = [
      # ── Core Hyprland management ──────────────────────────────────────
      (execBind "SUPER + SHIFT + C" "${bin}/kill-active.sh")
      (execBind "SUPER + SHIFT + K" "hyprctl kill")
      (execBind "SUPER + SHIFT + Q" "${bin}/leave.sh")
      (execBind "SUPER + SHIFT + R" "${bin}/reload-config.sh")

      # ── Tiling / layout ───────────────────────────────────────────────
      (bind "SUPER + SHIFT + space" ''hl.dsp.window.float({ action = "toggle" })'')
      (bind "SUPER + ALT + space" ''hl.dsp.layout("togglesplit")'')
      (bind "SUPER + minus" ''hl.dsp.layout("togglesplit")'')
      (bind "SUPER + P" "hl.dsp.window.pseudo()")
      (execBind "SUPER + SHIFT + comma" "${bin}/switch-layout.sh")
      (bind "SUPER + T" "hl.dsp.group.toggle()")
      (bind "SUPER + SHIFT + T" "hl.dsp.window.move({ out_of_group = true })")
      (bind "SUPER + comma" "hl.dsp.group.next()")

      # ── Fullscreen ────────────────────────────────────────────────────
      (bind "SUPER + F" "hl.dsp.window.fullscreen({ mode = 0 })")
      (bind "SUPER + M" "hl.dsp.window.fullscreen({ mode = 1 })")
      # keep internal state (-1), set client state to fake-fullscreen (2)
      (bind "SUPER + SHIFT + F" "hl.dsp.window.fullscreen_state({ internal = -1, client = 2 })")

      # ── Window movement ───────────────────────────────────────────────
      (execBind "SUPER + left" "${bin}/move-window.sh l")
      (execBind "SUPER + right" "${bin}/move-window.sh r")
      (execBind "SUPER + up" "${bin}/move-window.sh u")
      (execBind "SUPER + down" "${bin}/move-window.sh d")
      (bind "SUPER + s" "hl.dsp.window.swap({ next = true })")
      (execBind "SUPER + SHIFT + left" "${bin}/send-window.sh l")
      (execBind "SUPER + SHIFT + right" "${bin}/send-window.sh r")
      (execBind "SUPER + SHIFT + up" "${bin}/send-window.sh u")
      (execBind "SUPER + SHIFT + down" "${bin}/send-window.sh d")

      # ── Focus ─────────────────────────────────────────────────────────
      (bind "SUPER + h" ''hl.dsp.focus({ direction = "left" })'')
      (bind "SUPER + l" ''hl.dsp.focus({ direction = "right" })'')
      (bind "SUPER + k" ''hl.dsp.focus({ direction = "up" })'')
      (bind "SUPER + j" ''hl.dsp.focus({ direction = "down" })'')
      (execBind "SUPER + SHIFT + tab" "${bin}/switch-workspace.sh previous")
      (bind "SUPER + ALT + left" ''hl.dsp.focus({ workspace = "-1" })'')
      (bind "SUPER + ALT + right" ''hl.dsp.focus({ workspace = "+1" })'')

      # ── Workspace scroll (mouse wheel) ────────────────────────────────
      (bind "SUPER + mouse_down" ''hl.dsp.focus({ workspace = "e+1" })'')
      (bind "SUPER + mouse_up" ''hl.dsp.focus({ workspace = "e-1" })'')

      # ── Mouse drag move/resize (lua has no bindm; use bind + mouse=true) ──
      (bindOpts "SUPER + mouse:272" "hl.dsp.window.drag()" { mouse = true; })
      (bindOpts "SUPER + mouse:273" "hl.dsp.window.resize()" { mouse = true; })

      # ── Resize (hold-to-repeat) ───────────────────────────────────────
      (bindOpts "SUPER + SHIFT + h" "hl.dsp.window.resize({ x = -25, y = 0, relative = true })" {
        repeating = true;
      })
      (bindOpts "SUPER + SHIFT + j" "hl.dsp.window.resize({ x = 0, y = 25, relative = true })" {
        repeating = true;
      })
      (bindOpts "SUPER + SHIFT + k" "hl.dsp.window.resize({ x = 0, y = -25, relative = true })" {
        repeating = true;
      })
      (bindOpts "SUPER + SHIFT + l" "hl.dsp.window.resize({ x = 25, y = 0, relative = true })" {
        repeating = true;
      })

      # ── Applications ──────────────────────────────────────────────────
      (execBind "Print" "${bin}/screenshot.sh")
      (execBind "SUPER + Return" "${bin}/term.sh")
      (execBind "SUPER + SHIFT + Return" "${bin}/term.sh")
      (execBind "SUPER + W" "${bin}/run-or-raise.sh firefox")
      (execBind "SUPER + ALT + Y" "${bin}/browser-run-or-raise.sh --title youtube --url https://www.youtube.com")
      (execBind "SUPER + ALT + Z" "${bin}/ms-teams-join-room.sh home-room")
      (execBind "SUPER + ALT + T" "${bin}/ms-teams-join-room.sh home-room")
      (execBind "SUPER + SHIFT + Z" "${bin}/bring-window.sh --fullscreen chrome")
      (execBind "SUPER + ALT + H" "${bin}/browser-run-or-raise.sh --url https://ha.brkn.lol --alt http://10.5.1.1:8123")
      (execBind "F1" "${bin}/scratchpad.sh term")
      (execBind "SUPER + E" "${bin}/scratchpad.sh files")
      (execBind "SUPER + SHIFT + V" "${bin}/scratchpad.sh audio")
      (execBind "SUPER + ALT + a" "obs-control alt")
      (execBind "SUPER + ALT + w" "obs-control webcam")
      (execBind "SUPER + ALT + f" "obs-control freeze")
      (execBind "SUPER + ALT + up" "obs-control thumbs-up")
      (execBind "SUPER + ALT + down" "obs-control thumbs-down")
      (execBind "SUPER + ALT + period" "obs-control emoji")
      (execBind "SUPER + R" "walker")
      (execBind "SUPER + period" "walker -m menus:emoji")
      (execBind "SUPER + ALT + c" "walker -m clipboard")
      (execBind "SUPER + ALT + v" "${bin}/clipboard-revert.sh --notify")
      (execBind "SUPER + ALT + m" "walker-menu misc")
      (execBind "SUPER + ALT + j" "walker-menu meetings")
      (execBind "SUPER + ALT + s" "walker-menu soundboard")
      (execBind "SUPER + SHIFT + s" "walker-menu soundboard stop")

      # ── Mouse / hints / submap entry ──────────────────────────────────
      (bind "SUPER + SHIFT + M" ''hl.dsp.submap("${mouseSubmap}")'')
      (execBind "SUPER + numbersign" "waypoint")
      (execBind "SUPER + SHIFT + H" "killall hints; hints")
      (bind "SUPER + ALT + R" ''hl.dsp.submap("${resizeSubmap}")'')

      # ── Media / brightness (locked = works on the lock screen) ────────
      (execBindLocked "XF86MonBrightnessUp" "${barify} brightness up")
      (execBindLocked "XF86MonBrightnessDown" "${barify} brightness down")
      (execBindLocked "XF86AudioRaiseVolume" "${barify} sink up")
      (execBindLocked "XF86AudioLowerVolume" "${barify} sink down")
      (execBindLocked "XF86AudioMute" "${barify} sink mute")
      (execBindLocked "XF86AudioMicMute" "obs-control toggle-mute")
      (execBindLocked "SUPER + space" "obs-control toggle-mute")
      (execBindLocked "XF86AudioPlay" "${playerctl} toggle")
      (execBindLocked "XF86AudioPause" "${playerctl} pause")
      (execBindLocked "XF86AudioNext" "${playerctl} next")
      (execBindLocked "XF86AudioPrev" "${playerctl} previous")
      (execBindLocked "CONTROL + ALT + up" "${playerctl} toggle")
      (execBindLocked "CONTROL + ALT + right" "${playerctl} next")
      (execBindLocked "CONTROL + ALT + left" "${playerctl} previous")
      (execBindLocked "SUPER + ALT + b" "obs-control brb --mute")
    ]
    ++ wsBinds;

    submaps = {
      "${mouseSubmap}".settings.bind = [
        (mv "right" "+25")
        (mv "left" "-25")
        (mv "up" "-y -25")
        (mv "down" "-y +25")
        (mv "SHIFT + right" "+50")
        (mv "SHIFT + left" "-50")
        (mv "SHIFT + up" "-y -50")
        (mv "SHIFT + down" "-y +50")
        (mv "ALT + right" "+5")
        (mv "ALT + left" "-5")
        (mv "ALT + up" "-y -5")
        (mv "ALT + down" "-y +5")

        (cl "return" null)
        (cl "space" null)
        (cl "SHIFT + return" "right")
        (cl "SHIFT + space" "right")
        (cl "ALT + return" "middle")
        (cl "ALT + space" "middle")

        (mouseto "SHIFT + 0" "0" "0")
        (mouseto "SHIFT + 1" "1" "0")
        (mouseto "SHIFT + 2" "1" "1")
        (mouseto "SHIFT + 3" "0" "1")
        (mouseto "0" "0.25" "0.25")
        (mouseto "1" "0.75" "0.25")
        (mouseto "2" "0.75" "0.75")
        (mouseto "3" "0.25" "0.75")

        (mouseBtn "SUPER + SHIFT + space" "down")
        (mouseBtn "SUPER + SHIFT + return" "down")
        (mouseBtn "SUPER + space" "up")
        (mouseBtn "SUPER + return" "up")

        (reset "escape")
        (reset "q")
      ];

      "${resizeSubmap}".settings.bind = [
        (bindOpts "right" "hl.dsp.window.resize({ x = 25, y = 0, relative = true })" { repeating = true; })
        (bindOpts "left" "hl.dsp.window.resize({ x = -25, y = 0, relative = true })" { repeating = true; })
        (bindOpts "up" "hl.dsp.window.resize({ x = 0, y = -25, relative = true })" { repeating = true; })
        (bindOpts "down" "hl.dsp.window.resize({ x = 0, y = 25, relative = true })" { repeating = true; })
        (reset "escape")
        (reset "return")
      ];
    };
  };
}
