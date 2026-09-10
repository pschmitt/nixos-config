# DankMaterialShell — opt-in Quickshell bar on all laptops (ge2/gk4/x13),
# alongside the custom quickshell-bar in home-manager/gui/hyprland/quickshell-bar
# and Noctalia (profiles/laptop/noctalia.nix), which is the default.
# SUPER+SHIFT+B (toggle-bar.sh) cycles waybar -> quickshell-bar -> dms -> noctalia.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  home-manager.users.${config.mainUser.username} = hmArgs: {
    programs.dank-material-shell = {
      enable = true;
      systemd.enable = true;
      # Critical notifications otherwise use the same accent color
      # (Theme.primary) as every other notification, indistinguishable on
      # a dynamic/wallpaper-derived theme. See pkgs/local/dms-shell-critical-notifications.
      package = pkgs.dms-shell-critical-notifications;
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
        # Android-style battery pill, ported from Noctalia's
        # pschmitt/battery-icon plugin. See pkgs/local/dms-battery-icon.
        batteryIcon.src = "${pkgs.dms-battery-icon}/share/dms-plugins/battery-icon";
        # Home Assistant AI usage quotas, ported from Noctalia's
        # pschmitt/ha-ai-usage plugin. See pkgs/local/dms-ha-ai-usage. Same
        # sops-nix secret files as profiles/laptop/noctalia.nix's copy of
        # this plugin -- both paths resolve to sops-nix runtime files, never
        # to values in the Nix store.
        haAiUsage = {
          src = "${pkgs.dms-ha-ai-usage}/share/dms-plugins/ha-ai-usage";
          settings = {
            server_file = hmArgs.config.sops.secrets."home-assistant/server".path;
            token_file = hmArgs.config.sops.secrets."home-assistant/token".path;
            refresh_interval = 60;
          };
        };
        # Screencast REC indicator, ported from Noctalia's pschmitt/screencast
        # plugin. Detection reuses pkgs/local/screencast-state (already
        # shared with quickshell-bar/waybar). See pkgs/local/dms-screencast.
        screencast.src = "${pkgs.dms-screencast}/share/dms-plugins/screencast";
      };
      # Declarative snapshot of ~/.config/DankMaterialShell/settings.json
      # (bar layout, theme, fonts) and plugin_settings.json (enabled
      # plugins). NOTE: this makes both files Nix-managed symlinks, so the
      # DMS settings UI / `dms ipc` can no longer save changes to them —
      # further tweaks have to go through this file + a redeploy.
      managePluginSettings = true;
      settings = builtins.fromJSON (builtins.readFile ./dank-material-shell-settings.json);
      # Same wallpaper Noctalia uses (profiles/laptop/noctalia.nix's own
      # `wallpaper.default.path`), ported over since DMS had none set.
      # wallpaperPath lives in session.json (~/.local/state/...), not
      # settings.json -- DMS keeps "what's currently displayed" separate
      # from "how the shell is configured". weatherLocation/Coordinates
      # here just preserve what was already live in that file before it
      # became Nix-managed (same settings.json/plugin_settings.json
      # trade-off below: DMS can no longer write session.json either, so
      # e.g. changing the weather city has to go through this file too).
      session = {
        wallpaperPath = "${config.mainUser.homeDirectory}/Pictures/Wallpapers/chill.png";
        weatherLocation = "Berlin";
        weatherCoordinates = "52.5173885,13.3951309";
      };
    };
    # Noctalia is the default bar (profiles/laptop/noctalia.nix), so neither
    # Waybar nor DMS should autostart with the graphical session — both stay
    # reachable via toggle-bar.sh (SUPER+SHIFT+B) regardless of this.
    systemd.user.services.waybar.Install.WantedBy = lib.mkForce [ ];
    systemd.user.services.dms.Install.WantedBy = lib.mkForce [ ];
    # These existed as plain runtime files from earlier live DMS/plugin
    # edits; force lets home-manager take over managing them now.
    xdg = {
      configFile."DankMaterialShell/settings.json".force = true;
      configFile."DankMaterialShell/plugin_settings.json".force = true;
      stateFile."DankMaterialShell/session.json".force = true;
    };
  };
}
