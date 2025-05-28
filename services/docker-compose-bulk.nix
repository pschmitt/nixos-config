{ pkgs, ... }:
{
  systemd.services.docker-compose-bulk-up = {
    after = [
      "network.target"
      "docker.service"
      "mnt-data.mount"
    ];
    requires = [
      "docker.service"
      "mnt-data.mount"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk up -d";
    };
  };
}
