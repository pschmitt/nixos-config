{
  config,
  lib,
  pkgs,
  ...
}:
let
  backend = config.virtualisation.oci-containers.backend;
  containerUnits = map (name: "${backend}-${name}.service") [
    "archivebox"
    "archivebox-scheduler"
    "archivebox-pihole"
    "archivebox-sonic"
    "dawarich"
    "dawarich-postgres"
    "dawarich-redis"
    "dawarich-sidekiq"
    "linkding"
    "linkding-media-archiver"
    "nextcloud"
    "nextcloud-postgres"
  ];
  networkSetup = pkgs.writeShellApplication {
    name = "rofl-10-container-networks";
    runtimeInputs = [ pkgs.docker ];
    text = ''
      ensure_network() {
        local name="$1"
        shift

        if ! docker network inspect "$name" >/dev/null 2>&1
        then
          docker network create "$@" "$name"
        fi
      }

      ensure_network archivebox_default
      ensure_network archivebox_dns --subnet 10.27.24.0/24
      ensure_network dawarich_dawarich
      ensure_network linkding_default
      ensure_network nextcloud_default
    '';
  };
in
{
  systemd.services.rofl-10-container-networks = {
    description = "Create Docker networks for declarative rofl-10 containers";
    wantedBy = [ "multi-user.target" ];
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    before = containerUnits;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = lib.getExe networkSetup;
  };
}
