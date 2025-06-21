{ pkgs, ... }:
{
  systemd.services.docker-compose-bulk-up = {
    after = [
      "docker.service"
      "mnt-data.mount"
      "network.target"
    ];

    requires = [
      "docker.service"
      "mnt-data.mount"
    ];

    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      EnvironmentFile = [
        "/etc/containers/env/netbird.env"
        "/etc/containers/env/tailscale.env"
      ];
    };

    script = "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk up -d";
  };
}
