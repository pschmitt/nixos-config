{
  config,
  inputs,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    # ffmpeg
    # libcamera
    inputs.nixos-raspberrypi.packages.${pkgs.system}.ffmpeg_7-headless
    inputs.nixos-raspberrypi.packages.${pkgs.system}.libcamera
    inputs.nixos-raspberrypi.packages.${pkgs.system}.raspberrypi-utils
    # inputs.nixos-raspberrypi.packages.${pkgs.system}.rpicam-apps
    v4l-utils

    # XXX do we need this? Does that even make sense?
    # Should be put that in hardware.firmware?
    # raspberrypifw
  ];

  users.users."${config.custom.username}".extraGroups = [
    "i2c"
    "video"
  ];

  hardware = {
    i2c.enable = true;

    raspberry-pi."4" = {
      # XXX Do we need to add this?
      apply-overlays-dtmerge.enable = true;

      i2c0.enable = true;
      i2c1.enable = true;
    };
    deviceTree = {
      enable = true;
      # name = "bcm2711-rpi-4-b.dtb";
      overlays = [
        {
          name = "imx219";
          dtboFile = "${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/imx219.dtbo";
        }
      ];
    };
  };

  boot.kernelModules = [
    "i2c-dev"
    "i2c-bcm2835"
    "bcm2835-unicam"
    "imx219"
  ];

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
