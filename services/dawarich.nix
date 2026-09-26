{
  config,
  lib,
  pkgs,
  ...
}:
let
  backend = config.virtualisation.oci-containers.backend;
  # renovate: datasource=docker depName=freikin/dawarich
  dawarichVersion = "1.15.2";
  # renovate: datasource=docker depName=postgis/postgis
  postgisVersion = "17-3.5-alpine";
  # renovate: datasource=docker depName=redis
  redisVersion = "8.10.2-alpine";
  units = map (name: "${backend}-${name}") [
    "dawarich"
    "dawarich-postgres"
    "dawarich-redis"
    "dawarich-sidekiq"
  ];
  mkMeshPortForwards = import ./mk-mesh-port-forwards.nix {
    inherit config lib pkgs;
  };
in
{
  sops.secrets."compose/dawarich/database-password" = config.sops.mkHostSecret {
    restartUnits = map (name: "${backend}-${name}.service") [
      "dawarich"
      "dawarich-postgres"
      "dawarich-sidekiq"
    ];
  };

  sops.templates = {
    "compose/dawarich.env".content = ''
      DATABASE_PASSWORD=${config.sops.placeholder."compose/dawarich/database-password"}
    '';
    "compose/dawarich-postgres.env".content = ''
      POSTGRES_PASSWORD=${config.sops.placeholder."compose/dawarich/database-password"}
    '';
    "compose/dawarich-sidekiq.env".content = ''
      DATABASE_PASSWORD=${config.sops.placeholder."compose/dawarich/database-password"}
    '';
  };

  systemd.services =
    mkMeshPortForwards { dawarich = 32927; }
    // lib.genAttrs units (unit: {
      requires = [ "rofl-10-container-networks.service" ];
      after = [ "rofl-10-container-networks.service" ];
      restartIfChanged = true;
      restartTriggers =
        if
          builtins.elem unit [
            "${backend}-dawarich"
            "${backend}-dawarich-sidekiq"
          ]
        then
          [ dawarichVersion ]
        else if unit == "${backend}-dawarich-postgres" then
          [ postgisVersion ]
        else
          [ redisVersion ];
    });

  services.containerServices.services.dawarich = {
    port = 32927;
    hosts = [
      "dawarich.${config.domains.main}"
      "location.${config.domains.main}"
    ];
    monitoring = {
      path = "/api/v1/health";
      restart.systemdUnit = "${backend}-dawarich.service";
    };
  };

  virtualisation.oci-containers.containers = {
    dawarich = {
      image = "freikin/dawarich:${dawarichVersion}";
      autoStart = true;
      dependsOn = [
        "dawarich-postgres"
        "dawarich-redis"
      ];
      cmd = [
        "bin/rails"
        "server"
        "-p"
        "3000"
        "-b"
        "::"
      ];
      entrypoint = "web-entrypoint.sh";
      environment = {
        APPLICATION_HOSTS = "dawarich.brkn.lol,location.brkn.lol,127.0.0.1";
        APPLICATION_PROTOCOL = "http";
        DATABASE_HOST = "dawarich_db";
        DATABASE_NAME = "dawarich_development";
        DATABASE_USERNAME = "postgres";
        MIN_MINUTES_SPENT_IN_CITY = "60";
        PROMETHEUS_EXPORTER_ENABLED = "false";
        PROMETHEUS_EXPORTER_HOST = "0.0.0.0";
        PROMETHEUS_EXPORTER_PORT = "9394";
        RAILS_ENV = "development";
        REDIS_URL = "redis://dawarich_redis:6379";
        SELF_HOSTED = "true";
        STORE_GEODATA = "true";
        TIME_ZONE = "Europe/Berlin";
      };
      environmentFiles = [ config.sops.templates."compose/dawarich.env".path ];
      extraOptions = [
        "--health-cmd=wget -qO - http://127.0.0.1:3000/api/v1/health | grep -q '\"status\"\\s*:\\s*\"ok\"'"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=30"
        "--health-start-period=30s"
      ];
      networks = [ "dawarich_dawarich" ];
      ports = [ "127.0.0.1:32927:3000" ];
      volumes = [
        "/srv/dawarich/data/public:/var/app/public"
        "/srv/dawarich/data/watched:/var/app/tmp/imports/watched"
        "/srv/dawarich/data/storage:/var/app/storage"
      ];
    };

    dawarich-postgres = {
      image = "postgis/postgis:${postgisVersion}";
      autoStart = true;
      environment.POSTGRES_USER = "postgres";
      environmentFiles = [ config.sops.templates."compose/dawarich-postgres.env".path ];
      extraOptions = [
        "--network-alias=dawarich_db"
        "--health-cmd=pg_isready -U postgres -d dawarich_development"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
      networks = [ "dawarich_dawarich" ];
      volumes = [
        "/srv/dawarich/data/psql:/var/lib/postgresql/data"
        "/srv/dawarich/data/shared:/var/shared"
      ];
    };

    dawarich-redis = {
      image = "redis:${redisVersion}";
      autoStart = true;
      cmd = [ "redis-server" ];
      extraOptions = [
        "--network-alias=dawarich_redis"
        "--health-cmd=redis-cli --raw incr ping"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
      networks = [ "dawarich_dawarich" ];
      volumes = [ "/srv/dawarich/data/shared:/data" ];
    };

    dawarich-sidekiq = {
      image = "freikin/dawarich:${dawarichVersion}";
      autoStart = true;
      cmd = [ "sidekiq" ];
      dependsOn = [
        "dawarich"
        "dawarich-postgres"
        "dawarich-redis"
      ];
      entrypoint = "sidekiq-entrypoint.sh";
      environment = {
        APPLICATION_HOSTS = "localhost";
        APPLICATION_PROTOCOL = "http";
        BACKGROUND_PROCESSING_CONCURRENCY = "10";
        DATABASE_HOST = "dawarich_db";
        DATABASE_NAME = "dawarich_development";
        DATABASE_USERNAME = "postgres";
        PROMETHEUS_EXPORTER_ENABLED = "false";
        PROMETHEUS_EXPORTER_HOST = "dawarich";
        PROMETHEUS_EXPORTER_PORT = "9394";
        RAILS_ENV = "development";
        REDIS_URL = "redis://dawarich_redis:6379";
        SELF_HOSTED = "true";
        STORE_GEODATA = "true";
      };
      environmentFiles = [ config.sops.templates."compose/dawarich-sidekiq.env".path ];
      extraOptions = [
        "--health-cmd=pgrep -f sidekiq"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=30"
        "--health-start-period=30s"
      ];
      networks = [ "dawarich_dawarich" ];
      volumes = [
        "/srv/dawarich/data/public:/var/app/public"
        "/srv/dawarich/data/watched:/var/app/tmp/imports/watched"
        "/srv/dawarich/data/storage:/var/app/storage"
      ];
    };
  };
}
