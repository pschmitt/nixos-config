{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  ffmpegPkg = inputs.nixos-raspberrypi.packages.${stdenv.hostPlatform.system}.ffmpeg_7-headless;

  camPath = "cam";
  ffmpegBin = "${ffmpegPkg}/bin/ffmpeg";
  v4l2Dev = "/dev/video0";
in
{
  # --- SOPS: secrets for users/passwords ---
  sops.secrets."mediamtx/admin/username".sopsFile = config.custom.sopsFile;
  sops.secrets."mediamtx/admin/password".sopsFile = config.custom.sopsFile;
  sops.secrets."mediamtx/ffmpeg/username".sopsFile = config.custom.sopsFile;
  sops.secrets."mediamtx/ffmpeg/password".sopsFile = config.custom.sopsFile;
  sops.secrets."mediamtx/frigate/username".sopsFile = config.custom.sopsFile;
  sops.secrets."mediamtx/frigate/password".sopsFile = config.custom.sopsFile;

  # Render the full mediamtx.yml with placeholders substituted by sops.
  sops.templates."mediamtx.yaml" = {
    content = ''
      logLevel: debug

      hls: false
      rtmp: false
      srt: false
      webrtc: true

      authMethod: internal
      authInternalUsers:
        - user: ${config.sops.placeholder."mediamtx/ffmpeg/username"}
          pass: ${config.sops.placeholder."mediamtx/ffmpeg/password"}
          ips: ["127.0.0.1"]
          permissions:
          - action: publish
            path: ${camPath}

        - user: ${config.sops.placeholder."mediamtx/frigate/username"}
          pass: ${config.sops.placeholder."mediamtx/frigate/password"}
          permissions:
          - action: read
            path: ${camPath}

        - user: ${config.sops.placeholder."mediamtx/admin/username"}
          pass: ${config.sops.placeholder."mediamtx/admin/password"}
          permissions:
          - action: read
            path: ${camPath}

      paths:
        ${camPath}:
          runOnDemand: >-
            ${ffmpegBin} -hide_banner -loglevel warning
            -fflags nobuffer -flags low_delay -use_wallclock_as_timestamps 1 -avioflags direct
            -f v4l2 -input_format h264 -framerate 15 -video_size 1280x720 -i ${v4l2Dev}
            -c:v copy -an
            -f rtsp rtsp://${config.sops.placeholder."mediamtx/ffmpeg/username"}:${
              config.sops.placeholder."mediamtx/ffmpeg/password"
            }@127.0.0.1:8554/${camPath}
          runOnDemandRestart: yes
          runOnDemandCloseAfter: 10s
    '';
    mode = "0440";
    owner = "root";
    group = "video";
    restartUnits = [ "mediamtx.service" ];
  };

  # Ensure the built-in module is OFF (we're rolling our own)
  services.mediamtx.enable = lib.mkForce false;

  # Custom MediaMTX unit
  systemd.services.mediamtx = {
    description = "MediaMTX (custom config, sops-templated)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    # TODO Don't run as root!
    # serviceConfig = {
    #   User = "mediamtx";
    #   DynamicUser = true;
    #   SupplementaryGroups = "video";
    #   Restart = "on-failure";
    # };

    script = "${pkgs.mediamtx}/bin/mediamtx ${config.sops.templates."mediamtx.yaml".path}";
  };

  # Open only what you need. Add 8889/8189 if you use the WebRTC page.
  # networking.firewall.allowedTCPPorts = [ 8554 ];
  # networking.firewall.allowedTCPPorts = [ 8554 8889 ]
  # networking.firewall.allowedUDPPorts = [ 8189 ]
}
