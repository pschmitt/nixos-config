{ lib, pkgs, ... }:
let
  inherit (lib.generators) mkLuaInline;

  hyprSymlink = pkgs.writeShellScriptBin "hypr-symlink-runtime" ''
    if [[ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" || -z "''${XDG_RUNTIME_DIR:-}" ]]
    then
      exit 1
    fi
    DEST="''${XDG_DATA_HOME:-''${HOME}/.local/share}/hyprland"
    rm -rf "''${DEST}"
    ln -s "''${XDG_RUNTIME_DIR}/hypr/''${HYPRLAND_INSTANCE_SIGNATURE}" "''${DEST}"
  '';

  hyprTmuxEnv = pkgs.writeShellScriptBin "hypr-tmux-env" ''
    TMUX_BIN=${pkgs.tmux}/bin/tmux
    "$TMUX_BIN" has-session -t main 2>/dev/null || exit 1

    "$TMUX_BIN" set-environment DISPLAY "''${DISPLAY:-}"
    "$TMUX_BIN" set-environment WAYLAND_DISPLAY "''${WAYLAND_DISPLAY:-}"

    if [[ -f "''${HOME}/.config/zsh/traps.zsh" ]]
    then
      ${pkgs.procps}/bin/killall -USR2 zsh
    fi
  '';

  hyprGnomeKeyring = pkgs.writeShellScriptBin "hypr-gnome-keyring-autounlock" ''
    # Trigger the gnome-keyring-auto-unlock service (sops-backed on ge2,
    # zhj fallback elsewhere) rather than calling zhj directly.
    ${pkgs.systemd}/bin/systemctl --user start gnome-keyring-auto-unlock.service
  '';

  hyprFixRootGui = pkgs.writeShellScriptBin "hypr-fix-root-gui" ''
    DISPLAY="''${DISPLAY:-:0}" ${pkgs.xhost}/bin/xhost si:localuser:root
  '';
in
{
  home.packages = [
    pkgs.xhost
  ];

  # exec-once equivalent: run helpers once when the compositor starts.
  wayland.windowManager.hyprland.settings.on = [
    {
      _args = [
        "hyprland.start"
        (mkLuaInline ''
          function()
              -- Propagate graphical session variables to systemd/DBus.
              hl.exec_cmd("dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_RUNTIME_DIR QT_QPA_PLATFORM SDL_VIDEODRIVER CLUTTER_BACKEND TERMINAL")
              -- walker and elephant can be activated before the Wayland session
              -- environment reaches the user manager, leaving their first start
              -- broken until a manual restart. Refresh them after importing the
              -- compositor environment so they come up correctly on login.
              hl.exec_cmd("systemctl --user restart --no-block walker.service elephant.service")
              -- Restart the portal so it picks up WAYLAND_DISPLAY (it may have
              -- started before Hyprland exported the display environment).
              hl.exec_cmd("systemctl --user restart xdg-desktop-portal")
              -- Symlink the Hyprland runtime socket dir into XDG_DATA_HOME.
              hl.exec_cmd("systemd-cat --identifier=hyprland-startup ${hyprSymlink}/bin/hypr-symlink-runtime")
              -- Re-export Wayland env into the running tmux session.
              hl.exec_cmd("systemd-cat --identifier=hyprland-startup ${hyprTmuxEnv}/bin/hypr-tmux-env")
              -- Auto-unlock the GNOME keyring.
              hl.exec_cmd("systemd-cat --identifier=hyprland-startup ${hyprGnomeKeyring}/bin/hypr-gnome-keyring-autounlock")
              -- Allow root GUI apps access to the X display.
              hl.exec_cmd("systemd-cat --identifier=hyprland-startup ${hyprFixRootGui}/bin/hypr-fix-root-gui")
              -- Preload Nautilus as a background service so first open is instant.
              hl.exec_cmd("systemd-cat --identifier=hyprland-startup nautilus --gapplication-service")
          end
        '')
      ];
    }
  ];
}
