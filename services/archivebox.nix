{
  config,
  lib,
  pkgs,
  ...
}:
let
  backend = config.virtualisation.oci-containers.backend;
  # renovate: datasource=docker depName=archivebox/archivebox
  archiveboxVersion = "0.9.51";
  # renovate: datasource=docker depName=pihole/pihole
  piholeVersion = "2026.09.0";
  # renovate: datasource=docker depName=valeriansaliou/sonic
  sonicVersion = "v1.10.1";
  units = map (name: "${backend}-${name}") [
    "archivebox"
    "archivebox-scheduler"
    "archivebox-pihole"
    "archivebox-sonic"
  ];
  mkMeshPortForwards = import ./mk-mesh-port-forwards.nix {
    inherit config lib pkgs;
  };
in
{
  sops.secrets = {
    "compose/archivebox/admin-password" = config.sops.mkHostSecret {
      restartUnits = [ "${backend}-archivebox.service" ];
    };
    "compose/archivebox/search-password" = config.sops.mkHostSecret {
      restartUnits = [
        "${backend}-archivebox.service"
        "${backend}-archivebox-sonic.service"
      ];
    };
    "compose/archivebox/pihole-password" = config.sops.mkHostSecret {
      restartUnits = [ "${backend}-archivebox-pihole.service" ];
    };
  };

  sops.templates = {
    "compose/archivebox.env".content = ''
      ADMIN_PASSWORD=${config.sops.placeholder."compose/archivebox/admin-password"}
      SEARCH_BACKEND_PASSWORD=${config.sops.placeholder."compose/archivebox/search-password"}
    '';
    "compose/archivebox-pihole.env".content = ''
      WEBPASSWORD=${config.sops.placeholder."compose/archivebox/pihole-password"}
    '';
    "compose/archivebox-sonic.env".content = ''
      SEARCH_BACKEND_PASSWORD=${config.sops.placeholder."compose/archivebox/search-password"}
    '';
  };

  systemd.services =
    mkMeshPortForwards { archivebox = 27244; }
    // lib.genAttrs units (unit: {
      requires = [ "rofl-10-container-networks.service" ];
      after = [ "rofl-10-container-networks.service" ];
      restartIfChanged = true;
      restartTriggers =
        if
          builtins.elem unit [
            "${backend}-archivebox"
            "${backend}-archivebox-scheduler"
          ]
        then
          [ archiveboxVersion ]
        else if unit == "${backend}-archivebox-pihole" then
          [ piholeVersion ]
        else
          [ sonicVersion ];
    });

  services.containerServices.services.archivebox = {
    port = 27244;
    hosts = [
      "arc.${config.domains.main}"
      "archive.${config.domains.main}"
      "archivebox.${config.domains.main}"
      "arc.${config.networking.hostName}.${config.domains.main}"
      "archive.${config.networking.hostName}.${config.domains.main}"
      "archivebox.${config.networking.hostName}.${config.domains.main}"
    ];
    monitoring.restart.systemdUnit = "${backend}-archivebox.service";
  };

  virtualisation.oci-containers.containers = {
    archivebox = {
      image = "archivebox/archivebox:${archiveboxVersion}";
      autoStart = true;
      environment = {
        ADMIN_USERNAME = "pschmitt";
        ALLOWED_HOSTS = "*";
        CSRF_TRUSTED_ORIGINS = "https://archivebox.brkn.lol";
        PUBLIC_ADD_VIEW = "False";
        PUBLIC_INDEX = "False";
        PUBLIC_SNAPSHOTS = "False";
        SEARCH_BACKEND_ENGINE = "sonic";
        SEARCH_BACKEND_HOST_NAME = "sonic";
      };
      environmentFiles = [ config.sops.templates."compose/archivebox.env".path ];
      networks = [ "archivebox_default" ];
      ports = [ "127.0.0.1:27244:8000" ];
      volumes = [ "/srv/archivebox/data:/data" ];
    };

    archivebox-scheduler = {
      image = "archivebox/archivebox:${archiveboxVersion}";
      autoStart = true;
      cmd = [
        "schedule"
        "--foreground"
        "--update"
        "--every=day"
      ];
      environment.TIMEOUT = "120";
      networks = [ "archivebox_default" ];
      volumes = [ "/srv/archivebox/data:/data" ];
    };

    archivebox-pihole = {
      image = "pihole/pihole:${piholeVersion}";
      autoStart = true;
      environment.DNSMASQ_LISTENING = "all";
      environmentFiles = [ config.sops.templates."compose/archivebox-pihole.env".path ];
      extraOptions = [ "--ip=10.27.24.53" ];
      networks = [ "archivebox_dns" ];
      ports = [ "127.0.0.1:8090:80" ];
    };

    archivebox-sonic = {
      image = "valeriansaliou/sonic:${sonicVersion}";
      autoStart = true;
      environmentFiles = [ config.sops.templates."compose/archivebox-sonic.env".path ];
      extraOptions = [ "--network-alias=sonic" ];
      networks = [ "archivebox_default" ];
      volumes = [ "/srv/archivebox/data/sonic:/var/lib/sonic/store" ];
    };
  };
}
