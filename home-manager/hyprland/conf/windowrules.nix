{ lib, ... }:
{
  # Mirrors ~/.config/hypr/config.d/windowrules.conf (screensharing + pinning rules).
  # Docs: https://wiki.hyprland.org/Configuring/Window-Rules/.
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
      # Helpful aliases for window classes/titles (from windowrules.conf).
      "$firefox_pip" = "class:^(firefox)$, title:^(Picture-in-Picture)$";
      "$firefox_sharing" = "class:^(firefox)$,title:^(.*Sharing Indicator)$";
      "$xdph" = "class:^(hyprland-share-picker)$";
      "$zoom" = "class:^(zoom)$";
      "$gcr" = "class:^(gcr-prompter)$";
      "$peeppee" = "class:^.*(-peepee)$";
      "$porn" = "title:.*(?i)porn.*";
      "$bitwarden" = "title:.*(?i)bitwarden.*";

      windowrule = lib.mkAfter [
        # Floating/PiP helpers.
        "float, $firefox_pip"
        "pin, $firefox_pip"
        # Firefox sharing indicator should never steal focus or resize things.
        "float, $firefox_sharing"
        "suppressevent fullscreen, $firefox_sharing"
        "suppressevent maximize, $firefox_sharing"
        # windowrulev2 pin for $firefox_sharing stayed commented-out upstream.
        # Share-picker + Zoom quirks.
        "pin,$xdph"
        "suppressevent fullscreen, $zoom"
        # GNOME keyring prompt rules.
        "pin, $gcr"
        "stayfocused, $gcr"
        "noscreenshare, $gcr"
        # Sensitive applications should never be shared.
        "noscreenshare, tag:noscreenshare"
        "noscreenshare, $peeppee"
        "noscreenshare, $porn"
        "noscreenshare, $bitwarden"
      ];
    }
  ];
}
