{
  config,
  lib,
  pkgs,
  ...
}:
let
  # List of Harmonia hosts with their respective configurations
  harmonia_hosts = [
    {
      domain = "cache.${config.networking.hostName}.nb.brkn.lol";
      basicAuth = false;
    }
    { domain = "cache.${config.networking.hostName}.brkn.lol"; }
  ];

  # primary host
  conditional_hosts = lib.optional (config.networking.hostName == "rofl-10") [
    { domain = "cache.brkn.lol"; }
    { domain = "nix-cache.brkn.lol"; }
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
        proxyPass = "http://${config.services.harmonia.settings.bind}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
        extraConfig = ''
          zstd on;
          zstd_types application/x-nix-archive;
        '';
      };
    };

  # Merge the common and conditional hosts
  all_hosts = harmonia_hosts ++ lib.flatten conditional_hosts;

  # Generate virtual hosts for each host
  virtualHosts = builtins.listToAttrs (
    map (host: {
      name = host.domain;
      value = generateVHost host;
    }) all_hosts
  );
in
{
  sops.secrets = {
    "nix/store/privkey" = {
      sopsFile = config.custom.sopsFile;
    };
    "nix/credentials/htpasswd" = {
      owner = "nginx";
    };
  };

  services.harmonia = {
    enable = true;
    signKeyPaths = [ config.sops.secrets."nix/store/privkey".path ];
    settings = {
      bind = "127.0.0.1:42766";
    };
  };

  services.nginx.virtualHosts = virtualHosts;

  nix.gc.dates = lib.mkForce "monthly";

  # Setup nix store signing key path, so that we can also leverage the nix cache
  # via ssh (which bypasses harmonia)
  nix.extraOptions = ''
    secret-key-files = ${config.sops.secrets."nix/store/privkey".path}
  '';

  services.monit.config = lib.mkAfter ''
    check host "harmonia" with address "cache.${config.networking.hostName}.brkn.lol"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart harmonia"
      if failed
        port 443
        protocol https
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
