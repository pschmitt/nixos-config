{
  config,
  lib,
  pkgs,
  ...
}:
let
  mainDomain = config.domains.main;
  netbirdDomain = config.domains.netbird;
  cfg = config.services.harmonia;

  # List of Harmonia hosts with their respective configurations
  harmonia_hosts = [
    {
      domain = "cache.${config.networking.hostName}.${netbirdDomain}";
      basicAuth = false;
    }
    { domain = "cache.${config.networking.hostName}.${mainDomain}"; }
  ];

  # Function to generate virtual host configuration
  generateVHost =
    {
      domain,
      basicAuth ? true,
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
  options.services.harmonia.extraVirtualHosts = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          domain = lib.mkOption {
            type = lib.types.str;
            description = "Virtual host domain name.";
          };
          basicAuth = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable HTTP basic auth for this virtual host.";
          };
        };
      }
    );
    default = [ ];
    description = "Additional Harmonia virtual hosts to define on this machine.";
  };

  sops.secrets = {
    "nix/store/privkey" = config.custom.mkSecret {
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
      check host "harmonia" with address "cache.${config.networking.hostName}.${mainDomain}"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart harmonia"
        if failed
          port 443
          protocol https status 401
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
    '';
  };

  nix.gc.dates = lib.mkForce "monthly";

  # Setup nix store signing key path, so that we can also leverage the nix cache
  # via ssh (which bypasses harmonia)
  nix.extraOptions = ''
    secret-key-files = ${config.sops.secrets."nix/store/privkey".path}
  '';
}
