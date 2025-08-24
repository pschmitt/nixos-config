{
  config,
  inputs,
  lib,
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

  # binaries & device
  ffmpegBin = "${ffmpegPkg}/bin/ffmpeg";
  v4l2Device = "/dev/video0";

  # local publish target for ffmpeg (auth only here)
  rtspLocal = "rtsp://$FFMPEG_USER:$FFMPEG_PASS@127.0.0.1:8554/${camPath}";

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

  sops = {
    secrets = {
      "mediamtx/admin/username" = {
        sopsFile = config.custom.sopsFile;
      };
      "mediamtx/admin/password" = {
        sopsFile = config.custom.sopsFile;
      };
      "mediamtx/ffmpeg/username" = {
        sopsFile = config.custom.sopsFile;
      };
      "mediamtx/ffmpeg/password" = {
        sopsFile = config.custom.sopsFile;
      };
      "mediamtx/frigate/username" = {
        sopsFile = config.custom.sopsFile;
      };
      "mediamtx/frigate/password" = {
        sopsFile = config.custom.sopsFile;
      };
    };

    templates = {
      mediamtxCredentials = {
        # NOTE the indices matter here
        # *and* we need to define the entire section here, mixing yaml and env
        # vars isn't supported
        # See:
        # https://github.com/bluenviron/mediamtx/discussions/3378
        content = ''
          FFMPEG_USER=${config.sops.placeholder."mediamtx/ffmpeg/username"}
          FFMPEG_PASS=${config.sops.placeholder."mediamtx/ffmpeg/password"}

          # MTX_AUTHMETHOD=internal

          MTX_AUTHINTERNALUSERS_0_USER=${config.sops.placeholder."mediamtx/ffmpeg/username"}
          MTX_AUTHINTERNALUSERS_0_PASS=${config.sops.placeholder."mediamtx/ffmpeg/password"}
          # MTX_AUTHINTERNALUSERS_0_IPS_0=127.0.0.1
          # MTX_AUTHINTERNALUSERS_0_PERMISSIONS_0_ACTION=publish
          # MTX_AUTHINTERNALUSERS_0_PERMISSIONS_0_PATH=${camPath}

          MTX_AUTHINTERNALUSERS_1_USER=${config.sops.placeholder."mediamtx/frigate/username"}
          MTX_AUTHINTERNALUSERS_1_PASS=${config.sops.placeholder."mediamtx/frigate/password"}
          # MTX_AUTHINTERNALUSERS_1_PERMISSIONS_0_ACTION=read
          # MTX_AUTHINTERNALUSERS_1_PERMISSIONS_0_PATH=${camPath}

          MTX_AUTHINTERNALUSERS_2_USER=${config.sops.placeholder."mediamtx/admin/username"}
          MTX_AUTHINTERNALUSERS_2_PASS=${config.sops.placeholder."mediamtx/admin/password"}
          # MTX_AUTHINTERNALUSERS_2_PERMISSIONS_0_ACTION=read
          # MTX_AUTHINTERNALUSERS_2_PERMISSIONS_0_PATH=${camPath}
        '';
        owner = "root";
        group = "video";
        mode = "0440";
        restartUnits = [ "mediamtx.service" ];
      };
    };
  };

  # inject secrets, warning this uses DynamicUser!
  systemd.services.mediamtx = {
    serviceConfig = {
      EnvironmentFile = config.sops.templates.mediamtxCredentials.path;
    };
  };

  services.mediamtx = {
    enable = true;

    # give the service access to /dev/video*
    allowVideoAccess = true;

    settings = {
      webrtc = true;
      # rtmp = false
      # hls = false
      # srt = false;

      # NOTE auth is configured via env vars above
      authMethod = "internal";

      authInternalUsers = [
        {
          user = "ffmpeg_placeholder";
          pass = "changeme";
          ips = [ "127.0.0.1" ];
          permissions = [
            {
              action = "publish";
              path = camPath;
            }
          ];
        }
        {
          user = "frigate_placeholder";
          pass = "changeme";
          permissions = [
            {
              action = "read";
              path = camPath;
            }
          ];
        }
        {
          user = "admin_placeholder";
          pass = "changeme";
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
