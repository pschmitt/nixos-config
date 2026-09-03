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
      # Colors sampled directly from the reference screenshot
      # (noctalia.dev/plugins/community/battery-power-management) — near
      # black surfaces + a pastel periwinkle accent. Not a Noctalia builtin;
      # that screenshot is almost certainly a wallpaper-derived scheme from
      # the plugin author's own machine, not one of the fixed palette names.
      customPalettes.Indigo =
        let
          dark = {
            mPrimary = "#B6C4FF";
            mOnPrimary = "#11131A";
            mSecondary = "#8FA8FF";
            mOnSecondary = "#11131A";
            mTertiary = "#C9B6FF";
            mOnTertiary = "#11131A";
            mError = "#FF6B81";
            mOnError = "#11131A";
            mSurface = "#11131A";
            mOnSurface = "#E8E8F0";
            mSurfaceVariant = "#1E1F27";
            mOnSurfaceVariant = "#9A9AAE";
            mOutline = "#33333F";
            mShadow = "#000000";
            mHover = "#262733";
            mOnHover = "#E8E8F0";
            terminal = {
              background = "#11131A";
              foreground = "#E8E8F0";
              cursor = "#B6C4FF";
              cursorText = "#11131A";
              selectionBg = "#262733";
              selectionFg = "#E8E8F0";
              normal = {
                black = "#11131A";
                red = "#FF6B81";
                green = "#8FA8FF";
                yellow = "#C9B6FF";
                blue = "#B6C4FF";
                magenta = "#C9B6FF";
                cyan = "#8FA8FF";
                white = "#E8E8F0";
              };
              bright = {
                black = "#33333F";
                red = "#FF6B81";
                green = "#8FA8FF";
                yellow = "#C9B6FF";
                blue = "#B6C4FF";
                magenta = "#C9B6FF";
                cyan = "#8FA8FF";
                white = "#FFFFFF";
              };
            };
          };
        in
        {
          inherit dark;
          light = dark;
        };
      # Started as a mirror of the DMS bar layout (workspaceSwitcher+
      # runningApps / weather+clock+timewarrior / music+systemTray+
      # syncshell+controlCenter+battery+notifications), since diverged a
      # bit on request (no dedicated control-center button — the
      # notifications widget still opens into it). OSD (volume/brightness/
      # mic/etc.) is native and on by default — no settings needed.
      # Everything beyond this is meant to be tuned live (Settings app /
      # ~/.config/noctalia/config.toml), same as DMS's settings.json began
      # as a live-edited snapshot before being made declarative.
      settings = {
        bar.main = {
          position = "top";
          margin_ends = 0; # span the full screen width, matching the DMS bar
          # No font_weight override: the SemiBold family above is already a
          # fixed-weight cut, and synthetic-bolding on top of it looked off.
          # No blanket per-widget capsule anymore: only workspaces/media get
          # their own ([widget.workspaces]/[widget.media] below), everything
          # else is either bare or bundled into a capsule_group below.
          capsule = false;
          capsule_padding = 12;
          start = [
            "workspaces"
            "taskbar"
          ];
          center = [
            "group:weather-date"
            "group:timewarrior"
          ];
          end = [
            "media"
            "media-gap"
            # "ai_usage" — disabled, see plugins.enabled below.
            "tray"
            "pschmitt/syncthing:bar"
            "network"
            "group:notif-battery"
          ];
          # A plugin widget referenced by its raw "author/plugin:entry" id
          # (or even given its own named instance) rejects a direct
          # `capsule = true` override as "unknown setting" — confirmed live,
          # not just a single-member-group quirk. capsule_group is the only
          # mechanism that actually applies a capsule to a plugin widget,
          # single member or not — it sets the spec through a different path
          # that bypasses that per-key validation.
          capsule_group = [
            {
              id = "weather-date";
              members = [
                "weather"
                "clock"
              ];
              padding = 12;
            }
            {
              id = "timewarrior";
              members = [ "pschmitt/timewarrior:bar" ];
              padding = 12;
            }
            {
              id = "notif-battery";
              members = [
                "pschmitt/battery-icon:bar"
                "notifications"
              ];
              padding = 12;
            }
          ];
        };
        plugins = {
          enabled = [
            # Syncthing status/control — fork of noctalia-dev/community-plugins'
            # rylos/syncthing (see pkgs/local/noctalia-syncthing) with a
            # tray-sized icon and the DMS syncshell widget's composited status
            # badges instead of a small logo + separate glyph. Its `url`/
            # `api_key` plugin settings aren't set here: they persist to
            # Noctalia's runtime state once entered in Settings -> Plugins, so
            # there's no secret to manage declaratively for a one-time local
            # setup.
            "pschmitt/syncthing"
            # Port of pkgs/local/dms-timewarrior — see pkgs/local/noctalia-timewarrior.
            "pschmitt/timewarrior"
            # Renders the charge percentage inside the battery icon itself
            # (Android status-bar style) — see pkgs/local/noctalia-battery-icon.
            "pschmitt/battery-icon"
            # Ad-hoc custom OSD toast, panel-only (no bar widget) — see
            # pkgs/local/noctalia-osd and pkgs/local/osd/osd.sh.
            "pschmitt/osd"
            # AI plan quota (community plugin, felipeartur/ai-usagebar) —
            # tried and disabled again: didn't like the look, and Codex
            # support wasn't solid. pkgs/local/ai-usagebar is still built
            # below in case it's worth another look later.
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
            {
              name = "local-battery-icon";
              kind = "path";
              location = "${pkgs.noctalia-battery-icon}/share/noctalia-plugins";
              enabled = true;
            }
            {
              name = "local-syncthing";
              kind = "path";
              location = "${pkgs.noctalia-syncthing}/share/noctalia-plugins";
              enabled = true;
            }
            {
              name = "local-osd";
              kind = "path";
              location = "${pkgs.noctalia-osd}/share/noctalia-plugins";
              enabled = true;
            }
          ];
        };
        weather.enabled = true;
        location.auto_locate = true;
        # Off by default in Noctalia; needed for any UI sound to play at
        # all, including the battery-icon plugin's opt-in plug/unplug
        # chimes (plugin_settings."pschmitt/battery-icon".charging_sound_enabled
        # below is still its own separate gate).
        audio.enable_sounds = true;
        # Control center, launcher, clipboard, and plugin panels (e.g.
        # syncthing's) felt too small; scale non-bar shell UI up ~15%.
        # Separate from bar.scale/[widget.*].scale, which only affect bar
        # widget content.
        accessibility.ui_scale = 1.15;
        shell.font_family = "ComicCode Nerd Font SemiBold"; # a distinct family/cut, not a weight variant
        theme = {
          mode = "dark";
          source = "custom";
          custom_palette = "Indigo";
        };
        # Control Center (which the notifications widget opens into, at its
        # "notifications" tab) is "attached" by default but still opens
        # centered on the bar rather than under the clicked widget.
        shell.panel.open_near_click_control_center = true;
        control_center.width = 900; # full-sidebar width in px (600-1200), default 700
        widget = {
          weather = {
            show_condition = false;
            icon_color = "primary";
          };
          workspaces = {
            style = "minimal";
            show_all_outputs = true;
            capsule = true;
          };
          # Shorter media pill: no artist line, truncate the title sooner,
          # a smaller album art icon, and scroll the title on hover instead
          # of always/never.
          media = {
            hide_artist = true;
            min_length = 120;
            max_length = 240;
            capsule = true;
            art_size = 18;
            title_scroll = "on_hover";
            hide_when_no_media = true;
          };
          network.show_label = false;
          media-gap = {
            type = "spacer";
            length = 100;
          };
          # ai_usage (felipeartur/ai-usagebar:bar) — disabled, see
          # plugins.enabled below.
        };
        # Plugin-level settings (Settings -> Plugins gear), see plugins.enabled
        # above. Role names here (e.g. "on_surface") are resolved against the
        # active custom palette by pkgs/local/noctalia-battery-icon's
        # service.luau before hitting ImageMagick.
        plugin_settings."pschmitt/battery-icon" = {
          # Full charge shouldn't be as loud as the low/medium warning tiers.
          high_color = "on_surface";
          charging_color = "secondary";
        };
      };
    };
    # Waybar was the default, then DMS; Noctalia takes over that role now,
    # so flip which one autostarts with the graphical session. toggle-bar.sh
    # can still cycle to any available bar regardless of this.
    systemd.user.services.waybar.Install.WantedBy = lib.mkForce [ ];
    # CLI kept on PATH for direct terminal use even with the
    # felipeartur/ai-usagebar bar widget disabled above.
    home.packages = [ pkgs.ai-usagebar ];
  };
}
