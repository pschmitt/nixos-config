{ config, inputs, pkgs, ... }:
{
  boot.kernelModules = [
    "bcm2835-unicam"
    "imx219"
  ];

  environment.systemPackages = with pkgs; [
    ffmpeg
    # libcamera
    v4l-utils

    # do we need this? Does that even make sense?
    raspberrypifw
  ];

  users.users."${config.custom.username}".extraGroups = [
    "i2c"
    "video"
  ];

  # XXX ???????
  hardware.deviceTree = {
    enable = true;
    overlays = [
      {
        name = "imx219";
        dtboFile = "${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/imx219.dtbo";
      }
      # or: { name = "ov5647"; dtbo = "${pkgs.raspberrypi-firmware}/share/raspberrypi/boot/overlays/ov5647.dtbo"; }
    ];
  };

  # XXX The mediamtx pkg does NOT include raspberry pi camera support!
  # services.mediamtx = {
  #   enable = true;
  #
  #   # Give the service access to /dev/video* etc.
  #   allowVideoAccess = true;
  #
  #   # MediaMTX settings map 1:1 to mediamtx.yml
  #   settings = {
  #     # Optional: enable WebRTC (nice for browsers)
  #     webrtc = true;
  #
  #     # Define one camera path called "cam"
  #     paths = {
  #       cam = {
  #         # Built-in Raspberry Pi camera source
  #         source = "rpiCamera";
  #
  #         # Useful tunables (adjust to taste/hardware)
  #         rpiCameraWidth = 1280;
  #         rpiCameraHeight = 720;
  #         rpiCameraFPS = 30;
  #         rpiCameraBitrate = 2000000; # ~2 Mbps
  #
  #         # Only power/encode when a client connects
  #         sourceOnDemand = true;
  #       };
  #     };
  #   };
  # };
}
