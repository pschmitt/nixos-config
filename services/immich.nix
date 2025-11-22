{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostnames = [
    "img.${config.custom.mainDomain}"
    "img.${config.networking.hostName}.${config.custom.mainDomain}"
    "immich.${config.custom.mainDomain}"
    "immich.${config.networking.hostName}.${config.custom.mainDomain}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;

  # immich-face-to-album
  persons = [
    "anika"
    "maya"
  ];
  faceToAlbum =
    let
      baseSecretPath = "immich/immich-face-to-album";
    in
    lib.foldl'
      (
        acc: name:
        let
          templateName = "immich-face-to-album-${name}";
        in
        {
          sopsSecrets = acc.sopsSecrets // {
            "${baseSecretPath}/faces/${name}" = {
              inherit (config.custom) sopsFile;
            };
            "${baseSecretPath}/albums/${name}" = {
              inherit (config.custom) sopsFile;
            };
          };

          sopsTemplates = acc.sopsTemplates // {
            "${templateName}" = {
              content = ''
                API_KEY="${config.sops.placeholder."${baseSecretPath}/apiKey"}"
                FACE="${config.sops.placeholder."${baseSecretPath}/faces/${name}"}"
                ALBUM="${config.sops.placeholder."${baseSecretPath}/albums/${name}"}"
              '';
              owner = config.services.immich.user;
            };
          };

          systemdServices = acc.systemdServices // {
            "${templateName}" = {
              description = "Run immich-face-to-album for ${lib.toUpper name}";
              after = [ "immich-server.service" ];
              requires = [ "immich-server.service" ];
              serviceConfig = {
                EnvironmentFile = config.sops.templates."${templateName}".path;
                ExecStart = ''
                  ${pkgs.immich-face-to-album}/bin/immich-face-to-album \
                  --server http://${config.services.immich.host}:${toString config.services.immich.port} \
                  --key "$API_KEY" \
                  --face "$FACE" \
                  --album "$ALBUM"
                '';
                User = config.services.immich.user;
                Type = "oneshot";
              };
            };
          };

          systemdTimers = acc.systemdTimers // {
            "${templateName}" = {
              description = "Run immich-face-to-album regularly for ${lib.toUpper name}";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "hourly";
                Persistent = true;
              };
            };
          };
        }
      )
      {
        sopsSecrets = {
          "${baseSecretPath}/apiKey" = {
            inherit (config.custom) sopsFile;
          };
        };
        sopsTemplates = { };
        systemdServices = { };
        systemdTimers = { };
      }
      persons;
in
{
  services = {
    immich = {
      enable = true;
      # immich fails to build on unstable as of 2024-12-29
      # Fix:
      # https://github.com/NixOS/nixpkgs/pull/369042
      # https://nixpkgs-tracker.ocfox.me/?pr=369042
      package = pkgs.master.immich;
      # NOTE listening on "localhost" leads to immich only listening on IPv6
      host = "127.0.0.1";
      port = 2283;
      mediaLocation = "/mnt/data/srv/immich/media";
    };

    nginx.virtualHosts."${primaryHost}" = {
      inherit serverAliases;
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://${config.services.immich.host}:${toString config.services.immich.port}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
        # Allow uploading large files
        # https://immich.app/docs/FAQ/#why-are-only-photos-and-not-videos-being-uploaded-to-immich
        extraConfig = ''
          client_max_body_size 50000M;
        '';
      };
    };

    monit.config = lib.mkAfter ''
      check host "immich" with address "${primaryHost}"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart immich-server"
        if failed
          port 443
          protocol https
          with timeout 15 seconds
          and certificate valid for 5 days
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  # immich-face-to-album
  sops.secrets = faceToAlbum.sopsSecrets;
  sops.templates = faceToAlbum.sopsTemplates;
  systemd.services = faceToAlbum.systemdServices;
  systemd.timers = faceToAlbum.systemdTimers;
}
