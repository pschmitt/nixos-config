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
  # XXX rpicam-apps build currently broken (sdl3 fails to build)
  # rpicamPkg = inputs.nixos-raspberrypi.packages.${pkgs.system}.rpicam-apps

  camPath = "cam";

  # credentials
  pubUser = "pub";
  pubPass = "pubpass";

  # TODO these are placeholders! -> sops!
  readUser = "cam";
  readPass = "readpass";

  # binaries & device
  ffmpegBin = "${ffmpegPkg}/bin/ffmpeg";
  v4l2Device = "/dev/video0";

  # local publish target for ffmpeg (auth only here)
  rtspLocal = "rtsp://${pubUser}:${pubPass}@127.0.0.1:8554/${camPath}";

  # single source of truth for the ffmpeg command (video-only, zero-copy H.264, low-latency)
  ffmpegCmd = ''
    ${ffmpegBin} -hide_banner -loglevel warning \
      -fflags nobuffer -flags low_delay -use_wallclock_as_timestamps 1 -avioflags direct \
      -f v4l2 -input_format h264 -framerate 15 -video_size 1280x720 -i ${v4l2Device} \
      -c:v copy -an \
      -f rtsp ${rtspLocal}
  '';
in
{
  # TODO: ensure /boot/firmware/config.txt has:
  # start_x=1
  # gpu_mem=128

  environment.systemPackages = with pkgs; [
    ffmpegPkg
    libcameraPkg
    raspberrypiUtilsPkg
    v4l-utils
  ];

  users.users."${config.custom.username}".extraGroups = [ "video" ];

  services.mediamtx = {
    enable = true;

    # give the service access to /dev/video*
    allowVideoAccess = true;

    settings = {
      webrtc = true;
      # rtmp = false; hls = false; srt = false;

      authMethod = "internal";
      authInternalUsers = [
        {
          user = pubUser;
          pass = pubPass;
          ips = [ "127.0.0.1" ];
          permissions = [
            {
              action = "publish";
              path = camPath;
            }
          ];
        }
        {
          user = readUser;
          pass = readPass;
          permissions = [
            {
              action = "read";
              path = camPath;
            }
          ];
        }
      ];

      paths."${camPath}" = {
        runOnDemand = ffmpegCmd;
        runOnDemandRestart = true;
        runOnDemandCloseAfter = "10s";
      };
    };
  };

  # Optional: open only what you need (RTSP/TCP 8554; add 8889 for WebRTC page)
  # networking.firewall.allowedTCPPorts = [ 8554 8889 ];
  # networking.firewall.allowedUDPPorts = [ 8189 ]; # WebRTC ICE/UDP
}
