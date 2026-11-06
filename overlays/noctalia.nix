{
  inputs,
  final,
  ...
}:
let
  inherit (final.stdenv.hostPlatform) system;
  base = inputs.noctalia.packages.${system}.default;
  fixes = import ./hotfixes/noctalia.nix;
in
{
  noctalia-lan-mouse = final.callPackage "${inputs.noctalia-plugins}/pkgs/noctalia-lan-mouse" { };

  noctalia = base.overrideAttrs (old: {
    # Keep feature additions and temporary corrections in the original order.
    patches =
      (old.patches or [ ])
      ++ [
        # Optional plugin notification icons and button glyph colors are API extensions.
        ./patches/noctalia/0001-plugin-notify-icon.patch
        fixes.sharpImages
        ./patches/noctalia/0004-button-content-color.patch
      ]
      ++ fixes.keyboardAndCapture
      ++ [
        # Persist caffeine (idle inhibitor) state across Noctalia restarts via
        # state.toml. Previously m_idleInhibitor was strictly in-memory and
        # defaulted to disabled on startup, losing caffeine whenever Noctalia
        # was restarted or reloaded. Also re-syncs inhibitor in setLogindService
        # so logind acquires the inhibit lock on startup if caffeine was enabled.
        ./patches/noctalia/0008-caffeine-state-persistence.patch

        # Voice-chain mute can differ from the default meeting mix, which also
        # carries the soundboard. Allow display-only mute-state overrides.
        ./patches/noctalia/0009-mic-osd-mute-override.patch

        # Opt-in intrinsic width for floating plugin panels. Used by the custom
        # OSD to fit the actual rendered text and glyph instead of width buckets.
        ./patches/noctalia/0010-plugin-panel-fit-content-width.patch

        # Offer browser buttons for HTTP(S) links in notification history.
        ./patches/noctalia/0011-notification-history-links.patch

        # Highlight URLs in notification toasts and history.
        ./patches/noctalia/0012-notification-link-styling.patch

        # Hit-test links in the text layout for individual URL clicks.
        ./patches/noctalia/0013-notification-link-hit-testing.patch

        # Mark opened notification links as visited for the current session.
        ./patches/noctalia/0014-notification-visited-links.patch

        # Show a pointer over notification links.
        ./patches/noctalia/0015-notification-link-cursor.patch

        # Pass a desktop activation token when opening notification links.
        ./patches/noctalia/0016-notification-link-activation.patch

        # Focus the configured URI handler when it already has a window.
        ./patches/noctalia/0017-notification-browser-focus.patch

        # Normalize Chromium urgency and offer a Chromium link action in history.
        ./patches/noctalia/0019-chromium-notifications.patch

        # Open Teams notification links in Chromium, including direct text clicks.
        ./patches/noctalia/0020-teams-links-chromium.patch

        # osd-show always used the configured osd.position, so an ad-hoc OSD
        # could not appear anywhere else without a persistent config-set. Accept
        # an optional "position" field (top_left ... center_right) in the JSON
        # payload that overrides the configured position for that OSD only; the
        # next OSD without one goes back to the config. Used by `osd --position`.
        ./patches/noctalia/0018-osd-show-position.patch
      ];
  });
}

# vim: set ft=nix et ts=2 sw=2 :
