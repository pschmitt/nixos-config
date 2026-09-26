{
  config,
  lib,
  pkgs,
  ...
}:
let
  backend = config.virtualisation.oci-containers.backend;
  # renovate: datasource=docker depName=sissbruecker/linkding
  linkdingVersion = "1.47.0";
  # renovate: datasource=docker depName=proog/linkding-media-archiver
  mediaArchiverVersion = "v0.6.0";
  linkdingPort = 54653;
  linkdingContainerPort = 9090;
  units = map (name: "${backend}-${name}") [
    "linkding"
    "linkding-media-archiver"
  ];
  mkMeshPortForwards = import ./mk-mesh-port-forwards.nix {
    inherit config lib pkgs;
  };
in
{
  sops.secrets."compose/linkding/media-archiver-token" = config.sops.mkHostSecret {
    restartUnits = [ "${backend}-linkding-media-archiver.service" ];
  };

  sops.templates."compose/linkding-media-archiver.env".content = ''
    LDMA_TOKEN=${config.sops.placeholder."compose/linkding/media-archiver-token"}
  '';

  systemd.services =
    mkMeshPortForwards { linkding = linkdingPort; }
    // lib.genAttrs units (unit: {
      requires = [ "rofl-10-container-networks.service" ];
      after = [ "rofl-10-container-networks.service" ];
      restartIfChanged = true;
      restartTriggers =
        if unit == "${backend}-linkding" then [ linkdingVersion ] else [ mediaArchiverVersion ];
    });

  services.containerServices.services.linkding = {
    port = linkdingPort;
    hosts = [
      "ld.${config.domains.main}"
      "linkding.${config.domains.main}"
    ];
    monitoring.restart.systemdUnit = "${backend}-linkding.service";
  };

  virtualisation.oci-containers.containers = {
    linkding = {
      image = "sissbruecker/linkding:${linkdingVersion}-plus";
      autoStart = true;
      environment = {
        LD_AUTH_PROXY_LOGOUT_URL = "";
        LD_AUTH_PROXY_USERNAME_HEADER = "";
        LD_CONTAINER_NAME = "linkding";
        LD_CONTEXT_PATH = "";
        LD_CSRF_TRUSTED_ORIGINS = "";
        LD_DB_DATABASE = "linkding";
        LD_DB_ENGINE = "sqlite";
        LD_DB_HOST = "";
        LD_DB_OPTIONS = "";
        LD_DB_PASSWORD = "";
        LD_DB_PORT = "";
        LD_DB_USER = "";
        LD_DISABLE_BACKGROUND_TASKS = "False";
        LD_DISABLE_URL_VALIDATION = "False";
        LD_ENABLE_AUTH_PROXY = "False";
        LD_HOST_DATA_DIR = "./data/linkding";
        LD_HOST_PORT = toString linkdingPort;
        LD_SUPERUSER_NAME = "";
        LD_SUPERUSER_PASSWORD = "";
      };
      networks = [ "linkding_default" ];
      ports = [ "127.0.0.1:${toString linkdingPort}:${toString linkdingContainerPort}" ];
      volumes = [ "/srv/linkding/data/linkding:/etc/linkding/data" ];
    };

    linkding-media-archiver = {
      image = "proog/linkding-media-archiver:${mediaArchiverVersion}";
      autoStart = true;
      dependsOn = [ "linkding" ];
      environment = {
        LDMA_BASEURL = "http://linkding:${toString linkdingContainerPort}";
        LDMA_SCAN_INTERVAL = "3600";
        LDMA_TAGS = "video music youtube";
      };
      environmentFiles = [ config.sops.templates."compose/linkding-media-archiver.env".path ];
      networks = [ "linkding_default" ];
    };
  };
}
