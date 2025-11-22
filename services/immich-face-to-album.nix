{
  config,
  lib,
  pkgs,
  ...
}:
let
  persons = [
    "anika"
    "maya"
  ];
  baseSecretPath = "immich/immich-face-to-album";

  faceToAlbum =
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
  sops.secrets = faceToAlbum.sopsSecrets;
  sops.templates = faceToAlbum.sopsTemplates;
  systemd.services = faceToAlbum.systemdServices;
  systemd.timers = faceToAlbum.systemdTimers;
}
