{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.mainUser) username;
  meshNodes = [
    "fnuc"
    "rofl-13"
    "rofl-14"
    "rofl-15"
  ];
in
{
  services.browser-daemon = {
    # fnuc also runs the Home Assistant VM: keep the browser load modest.
    maxSessions = lib.mkForce 5;
    # The live view's H.264 encoded on the Intel GPU: an animated page cost ~13%
    # of a core this way vs ~67% with x264 and ~147% as a JPEG screencast.
    video.encoder = "vaapi";
    # Render Chromium on the iGPU too: WebGL then reports the Intel GPU instead
    # of a software renderer, a bot tell.
    gpu.enable = true;
  };

  # VAAPI driver for the Comet Lake iGPU (Mesa ships none for Intel).
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];

  # Serves the vault of the live views (passkeys, logins; on any node) from
  # the rbw vault on fnuc, asking the phone to unlock rbw first when it is
  # locked.
  services.browser-daemon.secretAgent = {
    enable = true;
    user = username;
    nodes = map (h: "https://browser.${h}.${config.domains.netbird}") meshNodes;
    unlockWebhook = "http://10.5.1.1:8123/api/webhook/rbw_unlock_request";
    # A fill into a site the vault entry is not saved for notifies the phone.
    notifyWebhook = "http://10.5.1.1:8123/api/webhook/browser_daemon_any_site_fill";
  };
}
