{ inputs, pkgs, ... }:
let
  dcpPkg = inputs.docker-compose-bulk.packages.${pkgs.system}.docker-compose-bulk;
in
{
  environment.systemPackages = [ dcpPkg ];

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

    script = "${dcpPkg}/bin/docker-compose-bulk up -d";
  };
}
