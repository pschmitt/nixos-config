# Noctalia — trial replacement for DankMaterialShell as the default
# Quickshell bar on all laptops (ge2/gk4/x13). DMS itself is intentionally
# kept but not imported for now, see profiles/laptop/default.nix.
# SUPER+SHIFT+B (toggle-bar.sh) cycles waybar -> quickshell-bar -> noctalia
# (dms is skipped from the candidate list while its module isn't imported).
{
  config,
  pkgs,
  lib,
  ...
}:
{
  home-manager.users.${config.mainUser.username} = {
    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      # Mirrors the DMS bar layout (workspaceSwitcher+runningApps /
      # weather+clock+timewarrior / music+systemTray+syncshell+controlCenter+
      # battery+notifications) as closely as Noctalia's built-in widget set
      # allows. OSD (volume/brightness/mic/etc.) is native and on by default
      # — no settings needed. Everything beyond this starter layout is meant
      # to be tuned live (Settings app / ~/.config/noctalia/config.toml),
      # same as DMS's settings.json began as a live-edited snapshot before
      # being made declarative.
      settings = {
        bar.main = {
          position = "top";
          margin_ends = 0; # span the full screen width, matching the DMS bar
          font_weight = 700; # bold bar text
          start = [
            "workspaces"
            "taskbar"
          ];
          center = [
            "weather"
            "clock"
            "pschmitt/timewarrior:bar"
          ];
          end = [
            "media"
            "tray"
            "rylos/syncthing:bar"
            "control-center"
            "battery"
            "notifications"
          ];
        };
        plugins = {
          enabled = [
            # Syncthing status/control — same idea as
            # pkgs/local/syncshell-dank-widget for DMS, but this one ships
            # upstream (noctalia-dev/community-plugins). Its `url`/`api_key`
            # plugin settings aren't set here: they persist to Noctalia's
            # runtime state once entered in Settings -> Plugins, so there's
            # no secret to manage declaratively for a one-time local setup.
            "rylos/syncthing"
            # Port of pkgs/local/dms-timewarrior — see pkgs/local/noctalia-timewarrior.
            "pschmitt/timewarrior"
          ];
          # The official/community git sources aren't actually hardcoded —
          # they're seeded into runtime state on first launch, so declaring
          # them here too makes the config self-contained regardless of
          # that seeding (bit us once already after a state reset).
          source = [
            {
              name = "official";
              kind = "git";
              location = "https://github.com/noctalia-dev/official-plugins";
              enabled = true;
            }
            {
              name = "community";
              kind = "git";
              location = "https://github.com/noctalia-dev/community-plugins";
              enabled = true;
            }
            {
              name = "local";
              kind = "path";
              location = "${pkgs.noctalia-timewarrior}/share/noctalia-plugins";
              enabled = true;
            }
          ];
        };
        weather.enabled = true;
        location.auto_locate = true;
        shell.font_family = "ComicCode Nerd Font"; # matches mako.nix/DMS's fontName
        # Match kitty (Nord.conf, see ~/.config/kitty/kitty.conf) rather than
        # Noctalia's own default palette.
        theme = {
          mode = "dark";
          source = "builtin";
          builtin = "Nord";
        };
        # Control Center (which the notifications widget opens into, at its
        # "notifications" tab) is "attached" by default but still opens
        # centered on the bar rather than under the clicked widget.
        shell.panel.open_near_click_control_center = true;
        # Shorter media pill: no artist line, truncate the title sooner, and
        # a smaller album art icon.
        widget.media = {
          hide_artist = true;
          max_length = 140;
          art_size = 18;
        };
      };
    };
    # Waybar was the default, then DMS; Noctalia takes over that role now,
    # so flip which one autostarts with the graphical session. toggle-bar.sh
    # can still cycle to any available bar regardless of this.
    systemd.user.services.waybar.Install.WantedBy = lib.mkForce [ ];
  };
}
