# Noctalia — trial replacement for DankMaterialShell as the default
# Quickshell bar on all laptops (ge2/gk4/x13). DMS itself is intentionally
# kept but not imported for now, see profiles/laptop/default.nix.
# SUPER+SHIFT+B (toggle-bar.sh) cycles waybar -> quickshell-bar -> noctalia
# (dms is skipped from the candidate list while its module isn't imported).
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
let
  noctaliaPlugins = inputs.noctalia-plugins.packages.${pkgs.stdenv.hostPlatform.system};
  # A polling->events-API rewrite of this plugin's service.luau was tried
  # locally (overlays/patches/noctalia-plugins/0001-syncthing-events-api.patch)
  # to replace the fixed poll interval with Syncthing's /rest/events
  # long-poll. Reverted 2026-09-05: reconnecting after every event (or burst
  # of events — pause/resume-all, or just noctalia's own restart replaying a
  # backlog) intermittently raced noctalia's own httpStream stream-key reuse
  # and tripped its error budget, auto-disabling the plugin service with no
  # log output to point at a fix. Left in the patches directory in case a
  # future noctalia release closes that race and this becomes viable again.
in
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
          padding = 0; # main-axis padding from bar edges to the start/end widget sections — separate from margin_ends
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
          ];
          end = [
            "pschmitt/screencast:bar"
            "media"
            "media-gap"
            # "ai_usage" — disabled, see plugins.enabled below.
            "tray"
            "pschmitt/syncthing:bar"
            "group:volume"
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
                "pschmitt/timewarrior:bar"
              ];
              padding = 12;
              widget_spacing = 20; # gap between weather/clock/timewarrior
            }
            {
              id = "notif-battery";
              members = [
                "network"
                "pschmitt/fan-control:widget"
                "pschmitt/battery-icon:bar"
                "notifications"
              ];
              padding = 12;
            }
            {
              id = "volume";
              members = [
                "input-volume"
                "output-volume"
              ];
              padding = 12;
            }
          ];
        };
        plugins = {
          enabled = [
            # Syncthing status/control — fork of noctalia-dev/community-plugins'
            # rylos/syncthing (see pschmitt/noctalia-plugins) with a
            # tray-sized icon and the DMS syncshell widget's composited status
            # badges instead of a small logo + separate glyph. Its `url`/
            # `api_key` plugin settings aren't set here: they persist to
            # Noctalia's runtime state once entered in Settings -> Plugins, so
            # there's no secret to manage declaratively for a one-time local
            # setup.
            "pschmitt/syncthing"
            # Fan monitor/control — thinkpad_acpi (x13) or generic hwmon PWM
            # (Dell dell-smm-hwmon on ge2, GPD gpdfan on gk4), auto-detected.
            # Forked from the community piero-93/thinkpad-fan plugin — see
            # pschmitt/noctalia-plugins.
            "pschmitt/fan-control"
            # Port of pkgs/local/dms-timewarrior — see pschmitt/noctalia-plugins.
            "pschmitt/timewarrior"
            # Red-dot REC indicator while screensharing — see
            # pschmitt/noctalia-plugins, ported from the old Waybar
            # custom/screencast module.
            "pschmitt/screencast"
            # Renders the charge percentage inside the battery icon itself
            # (Android status-bar style) — see pschmitt/noctalia-plugins.
            "pschmitt/battery-icon"
            # Ad-hoc custom OSD toast, panel-only (no bar widget) — see
            # pschmitt/noctalia-plugins and pkgs/local/osd/osd.sh.
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
              name = "pschmitt-timewarrior";
              kind = "path";
              location = "${noctaliaPlugins.noctalia-timewarrior}/share/noctalia-plugins";
              enabled = true;
            }
            {
              name = "pschmitt-battery-icon";
              kind = "path";
              location = "${noctaliaPlugins.noctalia-battery-icon}/share/noctalia-plugins";
              enabled = true;
            }
            {
              name = "pschmitt-syncthing";
              kind = "path";
              location = "${noctaliaPlugins.noctalia-syncthing}/share/noctalia-plugins";
              enabled = true;
            }
            {
              name = "pschmitt-fan-control";
              kind = "path";
              location = "${noctaliaPlugins.noctalia-fan-control}/share/noctalia-plugins";
              enabled = true;
            }
            {
              name = "pschmitt-osd";
              kind = "path";
              location = "${noctaliaPlugins.noctalia-osd}/share/noctalia-plugins";
              enabled = true;
            }
            {
              name = "pschmitt-screencast";
              kind = "path";
              location = "${noctaliaPlugins.noctalia-screencast}/share/noctalia-plugins";
              enabled = true;
            }
          ];
        };
        weather.enabled = true;
        location.auto_locate = true;
        # Migrated from hyprpaper (home-manager/gui/hyprland/services/hyprpaper.nix,
        # now unimported) — same wallpaper, now managed natively by Noctalia
        # instead of a separate daemon fighting it for the same output.
        wallpaper = {
          enabled = true;
          default.path = "${config.mainUser.homeDirectory}/Pictures/Wallpapers/chill.png";
        };
        # Off by default in Noctalia; would also gate the battery-icon
        # plugin's opt-in plug/unplug chimes
        # (plugin_settings."pschmitt/battery-icon".charging_sound_enabled
        # below is its own separate gate, on this master switch) — left off,
        # no audible shell sounds wanted.
        audio.enable_sounds = false;
        # Control center, launcher, clipboard, and plugin panels (e.g.
        # syncthing's) felt too small; scale non-bar shell UI up ~15%.
        # Separate from bar.scale/[widget.*].scale, which only affect bar
        # widget content.
        accessibility.ui_scale = 1.15;
        shell = {
          font_family = "ComicCode Nerd Font SemiBold"; # a distinct family/cut, not a weight variant
          # Default is "{:%H:%M}" (std::chrono format spec) — add seconds to
          # the center bar's clock widget.
          time_format = "{:%H:%M:%S}";
          # Control Center (which the notifications widget opens into, at
          # its "notifications" tab) is "attached" by default but still
          # opens centered on the bar rather than under the clicked widget.
          panel.open_near_click_control_center = true;
        };
        theme = {
          mode = "dark";
          source = "custom";
          custom_palette = "Indigo";
        };
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
          input-volume = {
            type = "volume";
            device = "input";
            show_label = false; # mic level as a number isn't useful at a glance
          };
          output-volume = {
            type = "volume";
            device = "output";
          };
          media-gap = {
            type = "spacer";
            length = 100;
          };
          # ai_usage (felipeartur/ai-usagebar:bar) — disabled, see
          # plugins.enabled below.
        };
        # Plugin-level settings (Settings -> Plugins gear), see plugins.enabled
        # above. Role names here (e.g. "on_surface") are resolved against the
        # active custom palette by pschmitt/noctalia-plugins' battery-icon
        # service.luau before hitting ImageMagick.
        plugin_settings = {
          "pschmitt/fan-control" = {
            bar_display = "none"; # icon only
            color_trigger = "temp";
            temp_threshold_low = 60; # below: theme default (temp_low_color unset)
            temp_threshold_high = 70; # at/above: temp_high_color
            temp_mid_color = "#FFA500"; # 60-69°C: orange
            temp_high_color = "#EA4335"; # 70°C+: red
          };
          "pschmitt/battery-icon" = {
            # Material 3 Expressive battery colors (Google palette): neutral
            # normally, green while powered, and red at or below the
            # low-battery threshold.
            low_color = "#EA4335";
            medium_color = "#9AA0A6";
            high_color = "#9AA0A6";
            charging_color = "#34A853";
            text_color = "#202124";
            empty_color = "#F1F3F4";
          };
          "pschmitt/syncthing" = {
            # "Folder X is up to date" fires on every sync completion and
            # isn't interesting often enough to be worth a toast; errors and
            # device connect/disconnect notifications stay on.
            notify_folder_up_to_date = false;
          };
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

  # pschmitt/fan-control needs group-scoped write access to whichever fan
  # control interface is present, without running as root at runtime or
  # making it world-writable. Safe to apply on all three hosts unconditionally
  # (per AGENTS.md: no per-host branching in shared profiles) — a udev rule
  # for hardware that isn't present here is a no-op, and thinkpad_acpi's
  # fan_control module option is ignored when the module isn't loaded.
  # See plugins/fan-control/README.md in pschmitt/noctalia-plugins.
  users.groups.fan_ctl = { };
  users.users.${config.mainUser.username}.extraGroups = [ "fan_ctl" ];
  boot.extraModprobeConfig = ''
    options thinkpad_acpi fan_control=1
  '';
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="thinkpad_acpi", RUN+="${pkgs.coreutils}/bin/chgrp fan_ctl /proc/acpi/ibm/fan", RUN+="${pkgs.coreutils}/bin/chmod 0664 /proc/acpi/ibm/fan"
    SUBSYSTEM=="hwmon", ATTR{name}=="dell_smm", RUN+="${pkgs.bash}/bin/sh -c 'for f in /sys/%p/pwm*; do ${pkgs.coreutils}/bin/chgrp fan_ctl \"$$f\"; ${pkgs.coreutils}/bin/chmod 0664 \"$$f\"; done'"
    SUBSYSTEM=="hwmon", ATTR{name}=="gpdfan", RUN+="${pkgs.bash}/bin/sh -c 'for f in /sys/%p/pwm*; do ${pkgs.coreutils}/bin/chgrp fan_ctl \"$$f\"; ${pkgs.coreutils}/bin/chmod 0664 \"$$f\"; done'"
  '';
}
