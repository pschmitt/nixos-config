{ config, pkgs, ... }:
let
  inherit (config.mainUser) username;
  meshNodes = [
    "fnuc"
    "rofl-13"
    "rofl-14"
  ];
in
{
  services.browser-daemon = {
    # The live view's H.264 encoded on the Intel GPU: an animated page cost ~13%
    # of a core this way vs ~67% with x264 and ~147% as a JPEG screencast.
    video.encoder = "vaapi";
    # Render Chromium on the iGPU too: WebGL then reports the Intel GPU instead
    # of a software renderer, a bot tell.
    gpu.enable = true;
  };

  # VAAPI driver for the Comet Lake iGPU (Mesa ships none for Intel).
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];

  # The passkey helper runs as the vault's user and authenticates to the nodes
  # with the cluster secret: the same key, readable by that user.
  sops.secrets."browser-daemon/passkey-helper-secret" = {
    key = "browser-daemon/cluster-secret";
    owner = username;
    mode = "0400";
  };

  # Serves the passkeys approved in live views (on any node) from the rbw vault
  # on fnuc, asking the phone to unlock rbw first when it is locked.
  home-manager.users.${username}.systemd.user.services.browser-daemon-passkey-helper = {
    Unit.Description = "browser-daemon passkey helper (rbw)";
    Service = {
      ExecStart = builtins.concatStringsSep " " (
        [
          "${pkgs.browser-daemon}/bin/browser-daemon"
          "passkey-helper"
          "--cluster-secret-file"
          config.sops.secrets."browser-daemon/passkey-helper-secret".path
          "--rbw"
          "${pkgs.rbw}/bin/rbw"
          "--unlock-webhook"
          "http://10.5.1.1:8123/api/webhook/rbw_unlock_request"
          "--unlock-host"
          config.networking.hostName
        ]
        ++ map (h: "--node https://browser.${h}.${config.domains.netbird}") meshNodes
      );
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
