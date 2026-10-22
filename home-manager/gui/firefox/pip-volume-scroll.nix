{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.desktop.browser;

  # Snapshot of the Volume Scroll extension's settings (volumeScroll@zeph.no) so
  # the PiP window behaves and looks the same. Firefox keeps them in the profile
  # (storage.sync -> storage-sync-v2.sqlite), which Nix cannot read, so refresh
  # the JSON by hand (it keeps the same keys) after changing them in the extension:
  #   cp ~/.config/mozilla/firefox/default/storage-sync-v2.sqlite* /tmp/
  #   sqlite3 /tmp/storage-sync-v2.sqlite "select data from storage_sync_data \
  #     where ext_id='volumeScroll@zeph.no'" | jq --slurpfile cur \
  #     pip-volume-scroll.settings.json '.extensionData.globalSettings
  #     | with_entries(select(.key as $k | $cur[0] | has($k)))'
  volumeScrollSettings = builtins.readFile ./pip-volume-scroll.settings.json;

  pipVolumeScroll = builtins.replaceStrings [ "@VOLUME_SCROLL_SETTINGS@" ] [ volumeScrollSettings ] (
    builtins.readFile ./pip-volume-scroll.cfg.js
  );
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
