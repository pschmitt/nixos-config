{
  # Window rules -> hl.window_rule({ match = { ... }, ... }).
  # Docs: https://wiki.hypr.land/Configuring/Window-Rules/
  wayland.windowManager.hyprland.settings.window_rule =
    let
      pip = {
        class = "^(firefox)$";
        title = "^(Picture-in-Picture)$";
      };
      sharing = {
        class = "^(firefox)$";
        title = "^(.*Sharing Indicator)$";
      };
      xdph.class = "^(hyprland-share-picker)$";
      zoom.class = "^(zoom)$";
      gcr.class = "^(gcr-prompter)$";
      peeppee.class = "^.*(-peepee)$";
      porn.title = "(?i).*porn.*";
      bitwarden.title = "(?i).*bitwarden.*";
    in
    [
      # Firefox PiP: float + pin
      {
        match = pip;
        float = true;
      }
      {
        match = pip;
        pin = true;
      }

      # Firefox sharing indicator: never steal focus or trigger fullscreen
      {
        match = sharing;
        float = true;
      }
      {
        match = sharing;
        suppress_event = "fullscreen";
      }
      {
        match = sharing;
        suppress_event = "maximize";
      }

      # Share picker + Zoom quirks
      {
        match = xdph;
        pin = true;
      }
      {
        match = zoom;
        suppress_event = "fullscreen";
      }

      # GNOME keyring prompt
      {
        match = gcr;
        pin = true;
      }
      {
        match = gcr;
        stay_focused = true;
      }
      {
        match = gcr;
        no_screen_share = true;
      }

      # Sensitive applications should never be shared
      {
        match.tag = "noscreenshare";
        no_screen_share = true;
      }
      {
        match = peeppee;
        no_screen_share = true;
      }
      {
        match = porn;
        no_screen_share = true;
      }
      {
        match = bitwarden;
        no_screen_share = true;
      }
    ];
}
