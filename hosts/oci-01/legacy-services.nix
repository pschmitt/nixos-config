{ lib, pkgs, ... }:
let
  composeProjects = {
    traefik = "/srv/traefik";
  };

  mkComposeService = name: directory: {
    description = "Legacy Docker Compose project: ${name}";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "docker.service"
      "mnt-data.mount"
      "network-online.target"
    ];
    requires = [
      "docker.service"
      "mnt-data.mount"
    ];
    unitConfig.RequiresMountsFor = [ directory ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = directory;
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up --detach --remove-orphans";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
    };
  };
in
{
  systemd.tmpfiles.rules = [
    "L+ /srv - - - - /mnt/data/srv"
  ];

  systemd.services = lib.mapAttrs' (
    name: directory: lib.nameValuePair "legacy-compose-${name}" (mkComposeService name directory)
  ) composeProjects;
}
