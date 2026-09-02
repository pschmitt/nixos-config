# DankMaterialShell — default Quickshell bar on all laptops (ge2/gk4/x13),
# alongside the custom quickshell-bar in home-manager/gui/hyprland/quickshell-bar.
# SUPER+SHIFT+B (toggle-bar.sh) cycles waybar -> quickshell-bar -> dms.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  home-manager.users.${config.mainUser.username} = {
    programs.dank-material-shell = {
      enable = true;
      systemd.enable = true;
      # Raw pkgs.glib collides with the gsettings wrapper from
      # modules/theme.nix; the VPN widget isn't needed for this trial.
      enableVPN = false;
      plugins = {
        # Read-only Syncthing widget (syncthing.service already runs
        # system-wide via profiles/laptop/syncthing.nix). Re-themed with
        # Syncthing's own status icons, see pkgs/local/syncshell-dank-widget.
        syncshell.src = "${pkgs.syncshell-dank-widget}/share/dms-plugins/syncshell";
        # Port of the Waybar/quickshell-bar Timewarrior widget.
        timewarrior.src = "${pkgs.dms-timewarrior}/share/dms-plugins/timewarrior";
      };
      # Declarative snapshot of ~/.config/DankMaterialShell/settings.json
      # (bar layout, theme, fonts) and plugin_settings.json (enabled
      # plugins). NOTE: this makes both files Nix-managed symlinks, so the
      # DMS settings UI / `dms ipc` can no longer save changes to them —
      # further tweaks have to go through this file + a redeploy.
      managePluginSettings = true;
      settings = builtins.fromJSON (builtins.readFile ./dank-material-shell-settings.json);
    };
    # Waybar was the default; DMS takes over that role now, so flip which
    # one autostarts with the graphical session. toggle-bar.sh can still
    # cycle to either at any time regardless of this.
    systemd.user.services.waybar.Install.WantedBy = lib.mkForce [ ];
    # These existed as plain runtime files from earlier live DMS/plugin
    # edits; force lets home-manager take over managing them now.
    xdg.configFile."DankMaterialShell/settings.json".force = true;
    xdg.configFile."DankMaterialShell/plugin_settings.json".force = true;
  };
}
