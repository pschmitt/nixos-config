{ pkgs, ... }:
let
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
    "''${HOME}/bin/zhj" gnome-keyring::auto-unlock
  '';

  hyprFixRootGui = pkgs.writeShellScriptBin "hypr-fix-root-gui" ''
    DISPLAY="''${DISPLAY:-:0}" ${pkgs.xhost}/bin/xhost si:localuser:root
  '';
in
{
  home.packages = [
    pkgs.xhost
  ];

  wayland.windowManager.hyprland.settings."exec-once" = [
    "systemd-cat --identifier=hyprland-startup ${hyprSymlink}/bin/hypr-symlink-runtime"
    "systemd-cat --identifier=hyprland-startup ${hyprTmuxEnv}/bin/hypr-tmux-env"
    "systemd-cat --identifier=hyprland-startup ${hyprGnomeKeyring}/bin/hypr-gnome-keyring-autounlock"
    "systemd-cat --identifier=hyprland-startup ${hyprFixRootGui}/bin/hypr-fix-root-gui"
  ];
}
