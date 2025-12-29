{ lib, osConfig, ... }:
{
  # Docs: https://wiki.hyprland.org/Configuring/Window-Rules/.
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
      # Helpful aliases for window classes/titles (from windowrules.conf).
      "$firefox_pip" = "match:class ^(firefox)$, match:title ^(Picture-in-Picture)$";
      "$firefox_sharing" = "match:class ^(firefox)$, match:title ^(.*Sharing Indicator)$";
      "$xdph" = "match:class ^(hyprland-share-picker)$";
      "$zoom" = "match:class ^(zoom)$";
      "$gcr" = "match:class ^(gcr-prompter)$";
      "$peeppee" = "match:class ^.*(-peepee)$";
      "$porn" = "match:title (?i).*porn.*";
      "$bitwarden" = "match:title (?i).*bitwarden.*";

      windowrule = [
        # Floating/PiP helpers.
        "float on, $firefox_pip"
        "pin on, $firefox_pip"
        # Firefox sharing indicator should never steal focus or resize things.
        "float on, $firefox_sharing"
        "suppress_event fullscreen, $firefox_sharing"
        "suppress_event maximize, $firefox_sharing"
        # windowrulev2 pin for $firefox_sharing stayed commented-out upstream.
        # Share-picker + Zoom quirks.
        "pin on, $xdph"
        "suppress_event fullscreen, $zoom"
        # GNOME keyring prompt rules.
        "pin on, $gcr"
        "stay_focused on, $gcr"
        "no_screen_share on, $gcr"
        # Sensitive applications should never be shared.
        "no_screen_share on, match:tag noscreenshare"
        "no_screen_share on, $peeppee"
        "no_screen_share on, $porn"
        "no_screen_share on, $bitwarden"
      ]
      ++ lib.optionals (osConfig.networking.hostName != "ge2") [
        # Place Firefox on workspace 2 by default (except ge2 which has custom layout).
        "workspace 2, match:class ^(firefox)$"
      ];
    }
  ];
}
