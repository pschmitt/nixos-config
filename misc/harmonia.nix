{ config, lib, ... }:
{
  sops = {
    secrets = {
      "nix/store/privkey" = {
        sopsFile = config.custom.sopsFile;
      };
      "nix/credentials/htpasswd" = {
        owner = "nginx";
      };
    };
  };

  services.harmonia = {
    enable = true;
    signKeyPaths = [ config.sops.secrets."nix/store/privkey".path ];
    settings = {
      bind = "127.0.0.1:5000";
    };
  };

  services.nginx =
    let
      # A function to generate the virtual host configuration
      generateVHost =
        {
          domain,
          useBasicAuth ? false,
        }:
        {
          enableACME = true;
          acmeRoot = null; # FIXME https://github.com/NixOS/nixpkgs/issues/210807
          forceSSL = true;
          inherit (config.services.harmonia.settings) bind;

          basicAuthFile = if useBasicAuth then config.sops.secrets."nix/credentials/htpasswd".path else null;

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
    in
    {
      services.nginx.virtualHosts =
        let
          # Define your hostnames
          commonHosts = {
            "cache.${config.networking.hostName}.nb.brkn.lol" = generateVHost {
              domain = "cache.${config.networking.hostName}.nb.brkn.lol";
            };
            "cache.${config.networking.hostName}.brkn.lol" = generateVHost {
              domain = "cache.${config.networking.hostName}.brkn.lol";
              useBasicAuth = true;
            };
          };
          conditionalHosts = lib.mkIf (config.networking.hostName == "rofl-02") {
            "cache.brkn.lol" = generateVHost { domain = "cache.brkn.lol"; };
          };
        in
        commonHosts // conditionalHosts;
    };
}
