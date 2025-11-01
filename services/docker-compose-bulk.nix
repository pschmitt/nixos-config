{ inputs, pkgs, ... }:
let
  dcpPkg = inputs.docker-compose-bulk.packages.${pkgs.stdenv.hostPlatform.system}.docker-compose-bulk;
in
{
  environment.systemPackages = [ dcpPkg ];

  systemd.services.docker-compose-bulk-up = {
    after = [
      "docker.service"
      "mnt-data.mount"
      "network.target"
      "tailscaled.service"
      "netbird-netbird-io.service"
    ];

    requires = [
      "docker.service"
      "mnt-data.mount"
      "tailscaled.service"
      "netbird-netbird-io.service"
    ];

    wantedBy = [ "multi-user.target" ];

    script = "${dcpPkg}/bin/docker-compose-bulk up -d";
  };
}
