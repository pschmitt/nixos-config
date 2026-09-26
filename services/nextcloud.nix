{
  config,
  lib,
  pkgs,
  ...
}:
let
  backend = config.virtualisation.oci-containers.backend;
  # renovate: datasource=docker depName=lscr.io/linuxserver/nextcloud
  nextcloudVersion = "35.0.1-ls452";
  # renovate: datasource=docker depName=postgres
  postgresVersion = "18.6-bookworm";
  units = map (name: "${backend}-${name}") [
    "nextcloud"
    "nextcloud-postgres"
  ];
  domain = config.domains.main;
  mkHost = subdomain: "${subdomain}.${domain}";
  mkHostWithNode = subdomain: "${subdomain}.${config.networking.hostName}.${domain}";
  healthCheck = pkgs.writeShellScript "nextcloud-health-check" ''
    exec ${pkgs.curl}/bin/curl \
      --silent \
      --show-error \
      --fail \
      --insecure \
      --max-time 20 \
      --noproxy '*' \
      --resolve nextcloud.${domain}:63982:127.0.0.1 \
      "https://nextcloud.${domain}:63982/status.php" \
      >/dev/null
  '';
  mkMeshPortForwards = import ./mk-mesh-port-forwards.nix {
    inherit config lib pkgs;
  };
in
{
  sops.secrets."compose/nextcloud/postgres-password" = config.sops.mkHostSecret {
    restartUnits = [ "${backend}-nextcloud-postgres.service" ];
  };

  sops.templates."compose/nextcloud-postgres.env".content = ''
    POSTGRES_PASSWORD=${config.sops.placeholder."compose/nextcloud/postgres-password"}
  '';

  systemd.services =
    mkMeshPortForwards { nextcloud = 63982; }
    // lib.genAttrs units (unit: {
      requires = [
        "rofl-10-container-networks.service"
      ]
      ++ lib.optional (unit == "${backend}-nextcloud") "mnt-data.mount";
      restartIfChanged = true;
      restartTriggers =
        if unit == "${backend}-nextcloud" then [ nextcloudVersion ] else [ postgresVersion ];
      after = [
        "rofl-10-container-networks.service"
      ]
      ++ lib.optional (unit == "${backend}-nextcloud") "mnt-data.mount";
    });

  services.containerServices.services.nextcloud = {
    port = 63982;
    tls = true;
    hosts =
      map mkHost [
        "c"
        "nextcloud"
      ]
      ++ map mkHostWithNode [
        "c"
        "nextcloud"
      ];
    monitoring = {
      program = "${healthCheck}";
      restart.systemdUnit = "${backend}-nextcloud.service";
    };
    # Large files can take longer than NGINX's default 60 second timeout.
    extraLocationConfig = ''
      proxy_connect_timeout 3600;
      proxy_send_timeout 3600;
      proxy_read_timeout 3600;
    '';
  };

  virtualisation.oci-containers.containers = {
    # TODO: Switch to services.nextcloud after nixpkgs provides a package
    # compatible with the existing Nextcloud 35 data and we have a reviewed
    # conversion for the LinuxServer config directory.
    nextcloud = {
      image = "lscr.io/linuxserver/nextcloud:${nextcloudVersion}";
      autoStart = true;
      environment = {
        PGID = "1000";
        PUID = "1000";
        TZ = "Europe/Berlin";
      };
      networks = [ "nextcloud_default" ];
      ports = [ "127.0.0.1:63982:443" ];
      volumes = [
        "/srv/nextcloud/config/nextcloud:/config"
        "/srv/nextcloud/data/nextcloud:/data"
        "/mnt/data:/mnt/data"
        "/mnt/autorestic/mnt:/mnt/autorestic/mnt:shared"
      ];
    };

    nextcloud-postgres = {
      image = "postgres:${postgresVersion}";
      autoStart = true;
      environment.POSTGRES_USER = "nextcloud";
      environmentFiles = [ config.sops.templates."compose/nextcloud-postgres.env".path ];
      extraOptions = [ "--network-alias=postgres" ];
      networks = [ "nextcloud_default" ];
      volumes = [ "/srv/nextcloud/data/postgres:/var/lib/postgresql/data" ];
    };
  };
}
