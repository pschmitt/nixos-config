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
      # Load the autoconfig script (mozilla.cfg) that makes the PiP window react
      # to the mouse wheel. See pip-volume-scroll.cfg.js for what and why.
      package = pkgs.firefox.override {
        extraPrefs = builtins.readFile ./pip-volume-scroll.cfg.js;
      };

      profiles.default.settings = {
        # The script drives PiP's audio slider; this pref makes it available
        # (and visible on hover) in the PiP window
        "media.videocontrols.picture-in-picture.audio-toggle.enabled" = true;
      };
    };
  };
}
