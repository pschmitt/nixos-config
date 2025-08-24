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
  # XXX The rpicam-apps build is broken as of 2025-08-24
  # rpicamPkg = inputs.nixos-raspberrypi.packages.${pkgs.system}.rpicam-apps
in
{
  # TODO Add start_x=1 and gpu_mem=128 to /boot/firmware/config.txt

  environment.systemPackages = with pkgs; [
    ffmpegPkg
    libcameraPkg
    raspberrypiUtilsPkg
    v4l-utils
  ];

  users.users."${config.custom.username}".extraGroups = [ "video" ];

  services.mediamtx = {
    enable = true;

    # Give the service access to /dev/video* etc.
    allowVideoAccess = true;

    settings = {
      webrtc = true;

      # Define one camera path called "cam"
      paths = {
        cam = {
          # XXX The mediamtx pkg does NOT include raspberry pi camera support!
          # Built-in Raspberry Pi camera source
          # source = "rpiCamera";

          # NOTE We could use runOnInit/runOnInitRestart etc here
          runOnDemand = "${ffmpegPkg}/bin/ffmpeg -hide_banner -loglevel warning -f v4l2 -input_format h264 -framerate 15 -video_size 1280x720 -i /dev/video0 -c:v copy -an -f rtsp rtsp://127.0.0.1:8554/cam";
          runOnDemandRestart = true;
          runOnDemandCloseAfter = "10s";
        };
      };
    };
  };
}
