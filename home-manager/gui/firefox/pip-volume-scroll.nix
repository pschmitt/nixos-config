{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.desktop.browser;

  # Defaults for when Volume Scroll's sync storage cannot be read at runtime.
  volumeScrollSettings = builtins.readFile ./pip-volume-scroll.settings.json;

  pipVolumeScroll =
    builtins.replaceStrings
      [ "@VOLUME_SCROLL_SETTINGS@" "@PIP_VOLUME_BRIDGE@" ]
      [ volumeScrollSettings "file://${./.}/" ]
      (builtins.readFile ./pip-volume-scroll.cfg.js);
in
{
  config = lib.mkIf (cfg.enable && cfg.firefox.enable) {
    programs.firefox = {
      # Load the autoconfig script (mozilla.cfg) that makes the PiP window react
      # to the mouse wheel. See pip-volume-scroll.cfg.js for what and why.
      package = pkgs.firefox.override {
        extraPrefs = pipVolumeScroll;
      };

      profiles.default.settings = {
        # The script drives PiP's audio slider; this pref makes it available
        # (and visible on hover) in the PiP window
        "media.videocontrols.picture-in-picture.audio-toggle.enabled" = true;
      };
    };
  };
}
