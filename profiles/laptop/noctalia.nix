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

  # Noctalia's built-in "sticker" widget (used for the lockscreen avatar
  # below) has no rounding/mask setting of its own -- just image_path and
  # opacity -- so it renders ~/.face as a plain square. Pre-crop a circular
  # copy instead of asking Noctalia to do it.
  avatarCircularPath = "${config.mainUser.homeDirectory}/.local/share/noctalia-avatar-circular.png";

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
  home-manager.users.${config.mainUser.username} = hmArgs: {
    # Noctalia's own agent takes over (shell.polkit_agent below); only one
    # PolicyKit agent can register per session, so hyprpolkitagent has to go.
    services.hyprpolkitagent.enable = false;

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
            "group:ai-usage"
          ];
          center = [
            "group:weather-date"
          ];
          end = [
            "media"
            "media-gap"
            "group:sync-tray"
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
              # Single-member group purely to get a capsule around the AI usage
              # widget — see the note above on why `capsule = true` on the raw
              # plugin widget id doesn't work.
              id = "ai-usage";
              members = [
                "ha-ai-usage"
              ];
              padding = 12;
            }
            {
              id = "weather-date";
              members = [
                "weather"
                "clock"
                "timewarrior"
              ];
              padding = 12;
              widget_spacing = 20; # gap between weather/clock/timewarrior
            }
            {
              id = "notif-battery";
              members = [
                "network"
                "bluetooth"
                "battery-icon"
                "notifications"
              ];
              padding = 12;
            }
            {
              id = "sync-tray";
              members = [
                "tray"
                "syncthing"
              ];
              padding = 12;
            }
            {
              id = "volume";
              members = [
                # The REC indicator leads the audio controls: it is only ever
                # visible while a screencast is running, and when it appears it
                # should be the first thing in the capsule, not something
                # appended after the volume readout. Being member 0 costs
                # nothing now that this capsule is not an accordion (see
                # below) -- that index is only special while one is.
                "screencast"
                "input-volume"
                "output-volume"
              ];
              padding = 12;
              # No accordion any more. Noctalia keeps exactly one member of an
              # accordion capsule visible (index 0, the mic) and clips the rest
              # until hover, which would have made the REC dot a hover-only
              # indicator -- the one thing it must not be. So the whole capsule
              # stays unfolded: mic, output volume, and REC while sharing.
              accordion = false;
            }
          ];
        };
        plugins = {
          enabled = [
            # AI plan quotas, normalized and collected by Home Assistant. This
            # deliberately replaces codexbar-meter: the bar does not need to
            # duplicate provider authentication/polling that HA already owns.
            "pschmitt/ha-ai-usage"
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
              name = "pschmitt-ha-ai-usage";
              kind = "path";
              location = "${noctaliaPlugins.noctalia-ha-ai-usage}/share/noctalia-plugins";
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
          # Noctalia's own PolicyKit agent, in place of hyprpolkitagent
          # (disabled above) — that one registers but then fails its portal
          # handshake ("Could not register app ID: App info not found for
          # ''"), so prompts never reliably showed. Noctalia registers a
          # libpolkit-agent listener against a polkit_unix_session subject,
          # which needs XDG_SESSION_ID in the service environment — already
          # provided by the noctalia-launcher wrapper added for the
          # lockscreen (home-manager/gui/noctalia.nix). Panel placement
          # defaults to floating/center; see [shell.panel] polkit_placement.
          polkit_agent = true;
          # The keyboard-layout widget labels a layout by its xkb description
          # (`name[Group1]`), which it shortens via a built-in language table
          # ("German" -> DE, ...). Our custom layouts from
          # pkgs/local/custom-keymaps aren't in that table and would fall back
          # to "--", so map their descriptions to short labels by hand. Keys
          # must match the `name[Group1]` strings in
          # pkgs/local/custom-keymaps/symbols/* verbatim.
          keyboard_layout.custom_labels = {
            "Custom HHKB DE layout by pschmitt" = "hhkb-de";
            "gpdpocket4 custom DE layout" = "gpd-de";
            "gpdpocket4 custom US layout with some german-isms" = "gpd-us";
          };
          avatar_path = "${config.mainUser.homeDirectory}/.face";
        };
        # Replaces hyprlock as the default session locker on all laptops.
        # Blurred screenshot capture before lock (via wlr-screencopy) with
        # surface tint, PAM/fprintd fingerprint support, and lock-before-sleep.
        lockscreen = {
          enabled = true;
          lock_before_suspend = true;
          fingerprint = true;
          allow_empty_password = false;
          blurred_desktop = true;
          blur_intensity = 0.6;
          tint_intensity = 0.35;
          wallpaper = "${config.mainUser.homeDirectory}/Pictures/Wallpapers/chill.png";
        };
        # Absolute cx/cy/box_width/box_height (logical px) are required per
        # widget -- see the individual comments in mkOutputWidgets below --
        # so this whole block needs to know each target output's real
        # logical size (host.lockscreenOutputs, home-manager/host.nix, set
        # per host in hyprland/conf/host-specific/<host>.nix). Guessing this
        # is exactly the bug a previous version of this file had: it
        # shipped gk4's rotated 1536x960 numbers unconditionally, which
        # positioned everything too far left/up on ge2's unrotated
        # 1920x1200 panel for a few commits before this landed.
        #
        # Noctalia has no "one widget, every output" mode (that behavior is
        # bespoke-coded for its login_box only -- it auto-creates one login
        # box per connected output -- not something generic widget types get
        # for free), so showing the same layout everywhere means declaring
        # one full widget set per output, each with a unique id suffix.
        # mkOutputWidgets below builds that set for one `{ name,
        # logicalWidth, logicalHeight }` entry; lockscreen_widgets.widget
        # merges the sets for every entry in host.lockscreenOutputs.
        #
        # Every size/position below is a fraction of `h` (this output's
        # logical height), not `w`: gk4/ge2's internal panels happen to
        # share a 16:10 aspect ratio so a width-based fraction would have
        # looked identical, but ge2's external monitor is a 3440x1440
        # ultrawide -- sizing the (circular/square) avatar off width there
        # would stretch it into an ellipse. Basing every size off height
        # keeps proportions consistent across arbitrary aspect ratios; only
        # cx (horizontal centering) uses `w`.
        lockscreen_widgets =
          let
            mkOutputWidgets =
              {
                name,
                logicalWidth,
                logicalHeight,
              }:
              let
                w = logicalWidth;
                h = logicalHeight;
              in
              {
                # Small combined date+time pinned near the top, well out of
                # the way of the avatar+login block below (re-laid-out per
                # request: big avatar with the password field right under
                # it, date/time small and up top instead of a big centered
                # block). Was two separate widgets (date larger, time
                # smaller); merged back into one per request, kept at the
                # smaller time widget's box_height (0.03h) -- box_width
                # widened proportionally (0.16h -> 0.36h) since the combined
                # string is roughly 2.4x longer than "HH:MM:SS" alone.
                "datetime-${name}" = {
                  type = "clock";
                  output = name;
                  cx = w * 0.5;
                  cy = h * 0.035;
                  # Box_width was way wider than the actual text needed
                  # (0.6h background around ~19 chars of content) -- tightened
                  # to 0.4h. box_height bumped a bit more for a slightly
                  # bigger font (0.05h -> 0.06h).
                  box_width = h * 0.4;
                  box_height = h * 0.06;
                  settings = {
                    clock_style = "digital";
                    format = "{:%Y-%m-%d %H:%M:%S}";
                    # on_surface (bright/high-contrast) and on_surface_variant
                    # (standard muted secondary-text) both still read too
                    # bright here; outline is the dimmest role in the
                    # palette (normally used for borders/dividers).
                    color = "outline";
                    font_family = "ComicCode Nerd Font";
                    shadow = true;
                    center_text = true;
                    # Unlike every other widget here, this one keeps its
                    # background (common default: background_color =
                    # "surface", opacity 0.8) per request; radius bumped from
                    # the 12 default to 24 per request.
                    background_radius = 24.0;
                  };
                };
                # No custom plugin needed for the avatar: Noctalia ships a
                # built-in "sticker" desktop-widget type (image_path +
                # opacity) that lockscreen_widgets can use too, same as any
                # other type. background=false drops every widget type's
                # common card background/surface behind the content (default
                # true) -- we don't want a square card showing through the
                # circular crop.
                #
                # Bigger than before (0.15625h -> 0.22h) and centered with
                # the login box directly under it, per request -- no date/
                # time between them anymore, those moved to the top.
                "avatar-${name}" = {
                  type = "sticker";
                  output = name;
                  cx = w * 0.5;
                  cy = h * 0.41;
                  box_width = h * 0.22;
                  box_height = h * 0.22;
                  settings = {
                    image_path = avatarCircularPath;
                    opacity = 1.0;
                    background = false;
                  };
                };
                # No box_width/box_height here: the plugin's "lockscreen"
                # entry (noctalia-plugins battery-icon plugin.toml) reuses
                # bar.luau but doesn't declare its own icon_width/icon_height
                # settings (only the separate bar widget entry does, default
                # 36x18) — reading them back undeclared and forcing a
                # box-fit scale against that crashed Noctalia's Wayland
                # client outright (division against an unresolved natural
                # size -> an invalid buffer size sent to the compositor,
                # display_error=22). Declaring them explicitly here and
                # letting the widget auto-fit its own (now well-defined)
                # natural size avoids that path entirely.
                "battery-${name}" = {
                  type = "pschmitt/battery-icon:lockscreen";
                  output = name;
                  cx = w - (h * 0.04102);
                  cy = h * 0.97;
                  settings = {
                    icon_width = 64;
                    icon_height = 32;
                    background = false;
                  };
                };
                # Built-in "media_player" desktop-widget type, same as
                # clock/sticker above -- no plugin needed. hide_when_no_media
                # keeps it from occupying bottom-center space (and showing an
                # empty/idle player) when nothing is playing.
                "media-${name}" = {
                  type = "media_player";
                  output = name;
                  cx = w * 0.5;
                  cy = h * 0.9;
                  # Was a fixed 0.65h x 0.12h box (needed back when this had
                  # no background, to keep the art thumbnail + title + play
                  # button from being squeezed down to near-nothing). Now
                  # that `background` below draws a rounded rect, a fixed box
                  # much wider than the actual content left huge empty
                  # padding left/right of it. 0.0/0.0 auto-fits the box to
                  # content instead (default for every widget type), so the
                  # background hugs the art/title/controls tightly.
                  box_width = 0.0;
                  box_height = 0.0;
                  settings = {
                    layout = "horizontal";
                    color = "outline"; # match datetime-${name}'s color
                    font_family = "ComicCode Nerd Font";
                    shadow = true;
                    hide_when_no_media = true;
                    # Rounded background per request (widget default:
                    # background_color = "surface", opacity 0.8); radius
                    # bumped from the 12 default to 24 to match
                    # datetime-${name}'s background and the login box's
                    # input_radius.
                    background = true;
                    background_radius = 24.0;
                    # Default 10 hugged the art/title/controls too tightly
                    # against the now-rounder background edge.
                    background_padding = 18.0;
                  };
                };
                # Fixed widget-id convention for the login panel itself
                # (password field, weather/media row, session buttons) --
                # see docs.noctalia.dev/noctalia/configuration/lockscreen/
                # widgets. "compact" drops the weather/media/session-button
                # row for a slim password-only bar.
                #
                # cx/cy/box_width/box_height are required here even though we
                # want close to Noctalia's own default position: leaving them
                # unset (like we first tried) sends this widget through
                # Noctalia's auto-placement bootstrap, which persists a
                # *fresh default* settings snapshot (layout = "regular",
                # overwriting our "compact") into
                # ~/.local/state/noctalia/settings.toml -- silently
                # reverting our override even though config.toml still says
                # "compact". date/time/battery above don't hit this because
                # they already carry explicit geometry.
                # Directly under the (now bigger) avatar, close enough to
                # read as one unit rather than two separately-placed pieces.
                "lockscreen-login-box@${name}" = {
                  type = "login_box";
                  output = name;
                  cx = w * 0.5;
                  cy = h * 0.595;
                  # Close to the avatar's own width (0.22h) rather than a
                  # wide bar.
                  box_width = h * 0.30;
                  # 0.20417h (Noctalia's auto-computed default) was sized
                  # for the full "regular" panel with weather/media/session
                  # buttons; "compact" is just a password row and doesn't
                  # need nearly that much height -- shrunk for a slimmer,
                  # more GDM-like pill instead of a big mostly-empty card.
                  box_height = h * 0.09;
                  settings = {
                    layout = "compact";
                    # A visible outer panel (tried dark, then light/near-
                    # white -- see prior commits) always read as an ugly
                    # extra card. 0 opacity removes it outright; the actual
                    # password input keeps its own separate dark fill
                    # (input_opacity, untouched, defaults to 1.0) so it's
                    # still a clean, readable, self-contained pill on its
                    # own -- just without a panel floating behind it.
                    background_opacity = 0.0;
                    # Drops the separate "Place your finger on the reader"
                    # status card above the password row. Errors and Caps
                    # Lock warnings still show there when they happen.
                    show_unlock_hint = false;
                    # Drops the keyboard-layout chip ("DE") and the checkmark
                    # submit button beside the password field -- just the
                    # input itself. Enter still submits without the button.
                    show_keyboard_layout = false;
                    show_login_button = false;
                    # Password field corner radius per request (default 6).
                    input_radius = 24.0;
                  };
                };
              };
          in
          if hmArgs.config.host.lockscreenOutputs == [ ] then
            {
              # Unknown screen geometry (e.g. x13, not yet measured): skip
              # the custom layout rather than place widgets blindly. Noctalia
              # still locks natively via the plain `lockscreen` block above.
              enabled = false;
            }
          else
            {
              enabled = true;
              widget = lib.foldl' (
                acc: output: acc // (mkOutputWidgets output)
              ) { } hmArgs.config.host.lockscreenOutputs;
            };
        theme = {
          mode = "dark";
          source = "custom";
          custom_palette = "Indigo";
        };
        control_center.width = 900; # full-sidebar width in px (600-1200), default 700
        widget = {
          taskbar.scale = 1.25;
          weather = {
            show_condition = false;
            icon_color = "primary";
          };
          clock.format = "{:%H:%M:%S}";
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
          # Plugin widgets get named instances here rather than being
          # referenced by their raw "author/plugin:entry" ids in the lanes and
          # capsule groups above. Noctalia's bar editor only offers a widget's
          # settings gear when it can resolve a type for the reference, and
          # that lookup knows only [widget.<name>].type and built-in type names
          # (widgetTypeForReference(),
          # src/shell/settings/widget_settings_registry.cpp) — a bare plugin id
          # resolves to nothing, which is why none of these plugin widgets had
          # a settings gear, and why there was nowhere to set their
          # widget-scoped settings (icon_size and friends) from here either.
          # Same root cause as `capsule = true` being rejected on a raw plugin
          # id (see the note by capsule_group above).
          #
          # The trade-off that comes with the gear: what the settings UI writes
          # lands in ~/.local/state/noctalia/settings.toml, which outranks this
          # read-only config.toml — so a live tweak silently wins over any
          # `settings` declared here until it is cleared.
          timewarrior.type = "pschmitt/timewarrior:bar";
          ha-ai-usage.type = "pschmitt/ha-ai-usage:bar";
          battery-icon.type = "pschmitt/battery-icon:bar";
          syncthing.type = "pschmitt/syncthing:bar";
          screencast.type = "pschmitt/screencast:bar";
          # ai_usage (felipeartur/ai-usagebar:bar) — disabled, see
          # plugins.enabled below.
        };
        # Plugin-level settings (Settings -> Plugins gear), see plugins.enabled
        # above. Role names here (e.g. "on_surface") are resolved against the
        # active custom palette by pschmitt/noctalia-plugins' battery-icon
        # service.luau before hitting ImageMagick.
        plugin_settings = {
          "pschmitt/ha-ai-usage" = {
            # Both paths resolve to sops-nix runtime files, never to values in
            # the Nix store. The plugin reads them immediately before each
            # authenticated HA request.
            server_file = hmArgs.config.sops.secrets."home-assistant/server".path;
            token_file = hmArgs.config.sops.secrets."home-assistant/token".path;
            # Sub-path the panel's Home Assistant link icon opens, appended to
            # server_file's URL: the "mi casa" dashboard's AI-quotas card.
            dashboard_path = "/mi-casa/data#ai-quotas";
            # What the bar renders is plugin-scoped on purpose: config.toml is
            # a read-only home-manager symlink, so Noctalia's per-bar-widget
            # settings UI can never persist anything here. Only the widget's
            # pixel geometry (icon_size/progress_*/spacing) is left per-widget.
            # "short" = the 5h/session quota, "weekly" = the weekly one; the
            # tooltip lists both regardless of what the bar picks.
            metric_window = "weekly";
            # Comma-separated, case-insensitive fragments matched against the
            # discovered card labels (e.g. "Pro, Gemini, Codex"). Empty shows
            # every account Home Assistant discovers, capped by metric_limit.
            # The tooltip always lists every account regardless of this.
            card_filter = "Pro, Codex";
            metric_limit = 3;
            # Compact by default: glyph + progress bar, no text. Values, names
            # and reset times stay in the tooltip and the panel.
            display_mode = "summary";
          };
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
          "pschmitt/timewarrior" = {
            # Keep the bar slot through the working day even when the timer
            # is off, so the panel's Start button is reachable when it matters;
            # outside those hours an idle tracker is just noise and the slot
            # vanishes as it always did. Weekends are in scope too — that is
            # the trade for hiding it at 23:00 on a Tuesday. The plugin's
            # working_hours_start/end default to 06:00-20:00, which is the
            # wanted window. A running interval is shown whatever the hour.
            visibility = "working_hours";
            # Noctalia labels can't ask for an italic style, so the panel's
            # hint text gets there through a family that resolves to an italic
            # face — the fontconfig alias defined in profiles/gui/fonts.nix.
            italic_font_family = "ComicCode Italic";
            # The panel's start/stop button (and the widget's middle click)
            # would otherwise just run `timew start`/`timew stop`, which is
            # only half of a work day here: tw::work-start/stop also bring the
            # WIIT VPN up/down, start/stop the matching Taskwarrior task,
            # dismiss the timetracking reminder, and handle the falcon-sensor
            # VM, OBS and timewsync. Pointing the plugin at those keeps one
            # code path for "start working", whether it is triggered from a
            # shell or from the bar.
            #
            # zhj sources the interactive zsh plugins in a non-interactive
            # shell, which is what makes the tw:: aliases resolvable here; the
            # plugin runs these through /bin/sh -c, so the absolute path
            # matters (~/bin is on the interactive PATH, not the systemd user
            # service's).
            start_command = "${config.mainUser.homeDirectory}/bin/zhj tw::work-start";
            stop_command = "${config.mainUser.homeDirectory}/bin/zhj tw::work-stop";
            # tw::work-stop shuts the gec-debian VM down, closes Zoom/Teams
            # tabs and runs timewsync before it returns.
            command_timeout = 300;
            # Sync button in the panel header. tw::sync is the two-sided
            # version of the plugin's `timewsync` default: it syncs timewarrior
            # and then taskwarrior (twice, around the timew push), which is
            # what keeps the worklog task and its intervals consistent.
            # A year in hours is just a number; {days} splits it by the
            # plugin's hours_per_day (8 by default, i.e. work days), so the
            # Year box reads "149d 3h" instead of "1195h". Week and month stay
            # in hours, where the figure is still something to compare against
            # a day's or a week's target.
            year_time_format = "{days}d {hours}h";
            sync_enabled = true;
            sync_command = "${config.mainUser.homeDirectory}/bin/zhj taskwarrior::sync";
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
    # The Timewarrior Noctalia plugin runs `timew` directly. Keep it on the
    # same database as the shell/Waybar helpers; systemd user services do not
    # inherit the interactive shell's TIMEWARRIORDB environment.
    systemd.user.services.noctalia.Service.Environment = [
      "TIMEWARRIORDB=${config.mainUser.homeDirectory}/.config/timewarrior"
    ];
    # Regenerate the circular avatar crop (see avatarCircularPath above) on
    # every activation, same cadence as noctaliaResetState, so it follows
    # the source photo if that ever changes. Prefers the pre-cut
    # transparent-background photo (so the circle doesn't show a flat
    # backdrop color inside it -- geometric cropping alone can't remove
    # that) and falls back to ~/.face if it's absent on a given host.
    # Silently does nothing if neither exists rather than failing
    # activation over a cosmetic asset.
    home.activation.noctaliaAvatarCircularCrop = hmArgs.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      src="${config.mainUser.homeDirectory}/Pictures/Profile Pictures/profile-pic-square-no-bg.png"
      if [[ ! -f "$src" ]]; then
        src="${config.mainUser.homeDirectory}/.face"
      fi
      if [[ -f "$src" ]]; then
        run mkdir -p "$(${pkgs.coreutils}/bin/dirname "${avatarCircularPath}")"
        # -background none is required even though nothing here looks like
        # it fills a background: without it, -resize/-extent silently
        # flattens the source's own transparency to opaque white before
        # the circle mask ever runs (confirmed by inspecting the
        # intermediate image directly -- alpha was gone right after
        # -resize/-extent, mask math was never the problem).
        run ${pkgs.imagemagick}/bin/magick "$src" \
          -background none -resize 260x260^ -gravity center -extent 260x260 \
          \( -size 260x260 xc:none -fill white -draw "circle 130,130 130,0" \) \
          -alpha set -compose DstIn -composite \
          "${avatarCircularPath}"
      fi
    '';
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
