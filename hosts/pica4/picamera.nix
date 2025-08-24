{
  config,
  inputs,
  pkgs,
  ...
}:
let
  ffmpegPkg = inputs.nixos-raspberrypi.packages.${pkgs.system}.ffmpeg_7-headless;
  libcameraPkg = inputs.nixos-raspberrypi.packages.${pkgs.system}.libcamera;
  raspberrypiUtilsPkg = inputs.nixos-raspberrypi.packages.${pkgs.system}.raspberrypi-utils;
in
{
  environment.systemPackages = with pkgs; [
    # ffmpeg
    # libcamera
    # raspberrypi-utils
    libcameraPkg
    ffmpegPkg
    raspberrypiUtilsPkg
    # XXX The rpicam-apps build is broken as of 2025-08-24
    # inputs.nixos-raspberrypi.packages.${pkgs.system}.rpicam-apps
    v4l-utils
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
      # XXX This BORKS the pi! It won't boot!
      # name = "bcm2711-rpi-4-b.dtb";
      overlays = [
        # Raspberry Pi Camera Module v1
        {
          name = "ov5647";
          dtboFile = "${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/ov5647.dtbo";
        }
        # Raspberry Pi Camera Module v2.1
        {
          name = "imx219";
          dtboFile = "${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/imx219.dtbo";
        }
      ];
    };
  };

  boot.kernelModules = [
    "bcm2835-unicam"
    "bcm2835-v4l2"
    "i2c-bcm2835"
    "i2c-dev"
    "imx219"
    "ov5647"
  ];

  services.mediamtx = {
    enable = true;

    # Give the service access to /dev/video* etc.
    allowVideoAccess = true;

    # MediaMTX settings map 1:1 to mediamtx.yml
    settings = {
      # Optional: enable WebRTC (nice for browsers)
      webrtc = true;

      # Define one camera path called "cam"
      paths = {
        cam = {
          # XXX The mediamtx pkg does NOT include raspberry pi camera support!
          # Built-in Raspberry Pi camera source
          # source = "rpiCamera";
          runOnDemand = "${ffmpegPkg}/bin/ffmpeg -hide_banner -loglevel warning -f v4l2 -input_format h264 -framerate 15 -video_size 1280x720 -i /dev/video0 -c:v copy -an -f rtsp rtsp://127.0.0.1:8554/cam";
          runOnDemandRestart = true;
          runOnDemandCloseAfter = "10s";
        };
      };
    };
  };
}
