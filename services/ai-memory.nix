{
  config,
  inputs,
  pkgs,
  ...
}:
let
  domain = config.domains.main;
  host = "ai-memory.${domain}";
in
{
  imports = [ "${inputs.ai-memory}/nix/nixos-module.nix" ];

  # The same token is read by the clients (home-manager/devel/ai-memory.nix).
  sops.secrets."ai-memory/auth-token" = { };

  sops.templates."ai-memory.env" = {
    content = ''
      AI_MEMORY_AUTH_TOKEN=${config.sops.placeholder."ai-memory/auth-token"}
    '';
    restartUnits = [ "ai-memory.service" ];
  };

  services = {
    ai-memory = {
      enable = true;
      package = pkgs.llm-agents.ai-memory;
      dataDir = "/mnt/data/srv/ai-memory";
      port = 49374;
      environmentFile = config.sops.templates."ai-memory.env".path;
      settings.allowed_hosts = [
        host
        "127.0.0.1"
        "localhost"
      ];
    };

    nginx.virtualHosts.${host} = {
      forceSSL = true;
      useACMEHost = "wildcard.${domain}";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.ai-memory.port}";
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 300s;
        '';
      };
    };

    monit.checks.ai-memory = {
      type = "host";
      address = "127.0.0.1";
      group = "application";
      startProgram = "${config.systemd.package}/bin/systemctl start ai-memory.service";
      stopProgram = "${config.systemd.package}/bin/systemctl stop ai-memory.service";
      conditions = ''
        if failed port ${toString config.services.ai-memory.port} protocol http request "/" for 3 cycles then restart
        if 3 restarts within 5 cycles then alert
      '';
    };
  };
}
