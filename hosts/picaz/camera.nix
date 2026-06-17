{ pkgs, ... }:
let
  # withJanus pulls in janus-gateway → valgrind, which is not available on armv6l
  ustreamer = pkgs.ustreamer.override { withJanus = false; };
in
{
  users.groups.ustreamer = { };
  users.users.ustreamer = {
    isSystemUser = true;
    group = "ustreamer";
    extraGroups = [ "video" ];
  };

  systemd.services.ustreamer = {
    description = "uStreamer MJPEG camera server";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "dev-video0.device"
    ];
    requires = [ "dev-video0.device" ];

    serviceConfig = {
      ExecStart = toString [
        "${ustreamer}/bin/ustreamer"
        "--device=/dev/video0"
        "--host=0.0.0.0"
        "--port=8080"
        "--format=MJPEG"
        # single-core Zero W: one worker is enough, keeps CPU headroom
        "--workers=1"
        "--drop-same-frames=30"
      ];
      User = "ustreamer";
      Group = "ustreamer";
      SupplementaryGroups = "video";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
