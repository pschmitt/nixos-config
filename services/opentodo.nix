{
  config,
  lib,
  pkgs,
  ...
}:
let
  host = "todo.${config.domains.main}";
  port = 32038;
  dataDir = "/mnt/data/srv/opentodo";
  backend = config.virtualisation.oci-containers.backend;
  # renovate: datasource=docker depName=ghcr.io/opentodoapp/opentodo
  version = "1.11.0";
  healthCheck = pkgs.writeShellApplication {
    name = "opentodo-health-check";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      status=$(curl --fail --silent --show-error --output /dev/null --write-out '%{http_code}' \
        --header 'X-Forwarded-For: 127.0.0.1' \
        http://127.0.0.1:${toString port}/healthz)
      [[ "$status" == 200 ]]
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 65532 65532 - -"
  ];

  systemd.services."${backend}-opentodo" = {
    restartIfChanged = true;
    restartTriggers = [ version ];
  };

  virtualisation.oci-containers.containers.opentodo = {
    image = "ghcr.io/opentodoapp/opentodo:${version}";
    pull = "always";
    environment = {
      OPENTODO_BASE_URL = "https://${host}";
      OPENTODO_SETUP_CODE = "required";
      OPENTODO_OIDC_ISSUER = "https://auth.${config.domains.main}";
      OPENTODO_OIDC_CLIENT_ID = "opentodo";
      OPENTODO_OIDC_DISPLAY_NAME = "Authelia";
    };
    ports = [ "127.0.0.1:${toString port}:8080" ];
    volumes = [ "${dataDir}:/data" ];
    extraOptions = [
      "--security-opt=no-new-privileges:true"
      "--cap-drop=ALL"
    ];
  };

  services.containerServices.services.opentodo = {
    inherit port;
    hosts = [ host ];
    monitoring = {
      program = lib.getExe healthCheck;
      restart.systemdUnit = config.virtualisation.oci-containers.containers.opentodo.serviceName;
    };
  };
}
