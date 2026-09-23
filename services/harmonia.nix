{
  config,
  lib,
  pkgs,
  ...
}:
let
  mainDomain = config.domains.main;
  netbirdDomain = config.domains.netbird;
  hostName = config.networking.hostName;
  cfg = config.services.harmonia;

  # List of Harmonia hosts with their respective configurations
  harmonia_hosts = [
    {
      domain = "cache.${config.networking.hostName}.${netbirdDomain}";
      basicAuth = false;
    }
  ]
  ++ lib.optional cfg.exposeMainDomain { domain = "cache.${hostName}.${mainDomain}"; };

  # Function to generate virtual host configuration
  generateVHost =
    {
      basicAuth ? true,
      ...
    }:
    {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      basicAuthFile = if basicAuth then config.sops.secrets."nix/credentials/htpasswd".path else null;

      locations."/" = {
        proxyPass = "http://${config.services.harmonia.cache.settings.bind}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
        extraConfig = ''
          zstd on;
          zstd_types application/x-nix-archive;
        '';
      };
    };

  all_hosts = harmonia_hosts ++ cfg.extraVirtualHosts;

  # Generate virtual hosts for each host
  virtualHosts = builtins.listToAttrs (
    map (host: {
      name = host.domain;
      value = generateVHost host;
    }) all_hosts
  );
in
{
  config = {
    sops.secrets = {
      "nix/store/privkey" = config.sops.mkHostSecret {
      };
      "nix/credentials/htpasswd" = {
        owner = "nginx";
      };
    };

    services = {
      harmonia.cache = {
        enable = true;
        signKeyPaths = [ config.sops.secrets."nix/store/privkey".path ];
        settings = {
          bind = "127.0.0.1:42766";
        };
      };

      nginx.virtualHosts = virtualHosts;

      monit.config = lib.mkAfter ''
        check host "harmonia" with address "127.0.0.1"
          group services
          restart program = "${pkgs.systemd}/bin/systemctl restart harmonia"
          if failed
            port 42766
            protocol http request "/nix-cache-info" status 200
            with timeout 15 seconds
            for 3 cycles
          then restart
          if 3 restarts within 15 cycles then alert
      '';
    };

    nix.extraOptions = ''
      secret-key-files = ${config.sops.secrets."nix/store/privkey".path}
    '';
  };
}
