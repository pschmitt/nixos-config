{
  config,
  lib,
  pkgs,
  ...
}:
let
  n8nHost = "n8n.${config.domains.main}";
  n8nPort = 5678;
  n8nRunnerBrokerPort = 5679;

  n8nHomeDir = "/srv/n8n";
  n8nDataDir = "${n8nHomeDir}/data/n8n";

  containerBackend = config.virtualisation.oci-containers.backend;
  systemdUnit = "${containerBackend}-n8n";

  n8nVersion = "2.5.1";
  containerNetworkName = "n8n";

  authTokenPath = config.sops.secrets."n8n/runners/authToken".path;
in
{
  sops = {
    secrets = {
      "n8n/runners/authToken" = {
        inherit (config.custom) sopsFile;
        path = "/run/secrets/n8n-runners-authToken";
        mode = "0400";
        # Below needs to match the user inside the n8n container
        uid = 1000;
        gid = 1000;
      };
    };
    templates."n8n/runners/env" = {
      content = ''
        N8N_RUNNERS_AUTH_TOKEN=${config.sops.placeholder."n8n/runners/authToken"}
      '';
      mode = "0400";
      restartUnits = [ "${config.virtualisation.oci-containers.backend}-n8n-runner.service" ];
    };
  };

  services = {
    nginx.virtualHosts."${n8nHost}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString n8nPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    monit.config = lib.mkAfter ''
      check host "n8n" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart ${systemdUnit}.service"
        if failed
          port ${toString n8nPort}
          protocol http
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  virtualisation.oci-containers.containers = {
    n8n = {
      image = "n8nio/n8n:${n8nVersion}";
      autoStart = true;
      environment = {
        GENERIC_TIMEZONE = config.time.timeZone;
        TZ = config.time.timeZone;

        NODE_ENV = "production";

        # N8N_BASIC_AUTH_ACTIVE = "true";
        N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true";

        N8N_HOST = n8nHost;
        N8N_LISTEN_ADDRESS = "0.0.0.0";
        N8N_PORT = toString n8nPort;
        N8N_PROTOCOL = "https";

        N8N_RUNNERS_ENABLED = "true";
        N8N_RUNNERS_MODE = "external";
        N8N_RUNNERS_AUTH_TOKEN_FILE = authTokenPath;
        N8N_RUNNERS_BROKER_LISTEN_ADDRESS = "0.0.0.0";
        N8N_RUNNERS_BROKER_PORT = toString n8nRunnerBrokerPort;
        N8N_NATIVE_PYTHON_RUNNER = "true";

        # https://docs.n8n.io/hosting/configuration/configuration-examples/webhook-url/
        WEBHOOK_URL = "https://${n8nHost}/";
        N8N_PROXY_HOPS = "1";

        N8N_USER_FOLDER = "/data";
      };
      volumes = [
        "${n8nDataDir}:/data:rw"
        "${authTokenPath}:${authTokenPath}:ro"
      ];
      ports = [
        "127.0.0.1:${toString n8nPort}:${toString n8nPort}"
      ];
      networks = [ containerNetworkName ];
    };

    n8n-runner = {
      image = "n8nio/runners:${n8nVersion}";
      autoStart = true;
      dependsOn = [ "n8n" ];
      environment = {
        N8N_RUNNERS_TASK_BROKER_URI = "http://n8n:${toString n8nRunnerBrokerPort}";
      };
      environmentFiles = [
        config.sops.templates."n8n/runners/env".path
      ];
      volumes = [
        "${n8nHomeDir}/config/runners/n8n-task-runners.json:/etc/n8n-task-runners.json:ro"
      ];
      networks = [ containerNetworkName ];
    };
  };

  systemd.services."${systemdUnit}".preStart =
    let
      runtimePkg =
        if containerBackend == "docker" then
          pkgs.docker
        else if containerBackend == "podman" then
          pkgs.podman
        else
          throw "Unsupported OCI container backend: ${containerBackend}";
      runtimeBin = "${runtimePkg}/bin/${containerBackend}";
    in
    ''
      if ! ${runtimeBin} network inspect ${containerNetworkName} >/dev/null 2>&1
      then
        ${runtimeBin} network create ${containerNetworkName}
      fi
    '';
}
