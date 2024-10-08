{ config, ... }:
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

  services.nginx = {
    virtualHosts."cache.${config.networking.hostName}.nb.brkn.lol" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;

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

    virtualHosts."cache.${config.networking.hostName}.brkn.lol" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      basicAuthFile = config.sops.secrets."nix/credentials/htpasswd".path;

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
  };
}
