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
  n8nDataDir = "/srv/n8n/data/n8n";
  n8nStateDir = "/var/lib/n8n";
  runnerEnvFile = "n8n-runner.env";
in
{
  sops = {
    secrets = {
      "n8n/runners/authToken" = {
        inherit (config.custom) sopsFile;
        owner = "pschmitt";
        group = "pschmitt";
        mode = "0400";
      };
    };
    templates."${runnerEnvFile}" = {
      content = ''
        N8N_RUNNERS_AUTH_TOKEN=${config.sops.placeholder."n8n/runners/authToken"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "${config.virtualisation.oci-containers.backend}-n8n-runner.service" ];
    };
  };

  services = {
    n8n = {
      enable = true;
      environment = {
        GENERIC_TIMEZONE = "Europe/Berlin";
        N8N_BASIC_AUTH_ACTIVE = true;
        N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = true;
        N8N_HOST = n8nHost;
        N8N_LISTEN_ADDRESS = "127.0.0.1";
        N8N_PORT = n8nPort;
        N8N_PROTOCOL = "https";
        N8N_SECURE_COOKIE = false;
        NODE_ENV = "production";
        WEBHOOK_URL = "https://${n8nHost}/";
        N8N_RUNNERS_ENABLED = true;
        N8N_RUNNERS_MODE = "external";
        N8N_RUNNERS_AUTH_TOKEN_FILE = config.sops.secrets."n8n/runners/authToken".path;
        N8N_RUNNERS_BROKER_LISTEN_ADDRESS = "127.0.0.1";
        N8N_RUNNERS_BROKER_PORT = n8nRunnerBrokerPort;
        N8N_NATIVE_PYTHON_RUNNER = true;
      };
    };

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
      check host "n8n" with address "${n8nHost}"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart n8n.service"
        if failed
          port 443
          protocol https
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  systemd.services.n8n.serviceConfig = {
    DynamicUser = lib.mkForce false;
    Group = "pschmitt";
    User = "pschmitt";
    ReadWritePaths = [
      n8nDataDir
      n8nStateDir
    ];
  };

  fileSystems."${n8nStateDir}" = {
    device = n8nDataDir;
    options = [ "bind" ];
  };

  virtualisation.oci-containers.containers.n8n-runner = {
    image = "n8nio/runners:${config.services.n8n.package.version}";
    autoStart = true;
    extraOptions = [
      "--network=host"
    ];
    environment = {
      N8N_RUNNERS_TASK_BROKER_URI = "http://127.0.0.1:${toString n8nRunnerBrokerPort}";
    };
    environmentFiles = [
      config.sops.templates."${runnerEnvFile}".path
    ];
    volumes = [
      "/srv/n8n/config/runners/n8n-task-runners.json:/etc/n8n-task-runners.json:ro"
    ];
  };
}
