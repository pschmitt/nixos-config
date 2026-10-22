{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.desktop.browser;
in
{
  config = lib.mkIf (cfg.enable && cfg.firefox.enable) {
    programs.firefox = {
      # Autoconfig script, see the file for details
      package = pkgs.firefox.override {
        extraPrefs = builtins.readFile ./pip-volume-scroll.cfg.js;
      };

      profiles.default.settings = {
        # Show the PiP volume slider, the wheel handler drives it
        "media.videocontrols.picture-in-picture.audio-toggle.enabled" = true;
      };
    };
  };
}
