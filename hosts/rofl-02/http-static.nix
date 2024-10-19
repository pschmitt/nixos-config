{ config, pkgs, ... }:

{
  services.nginx.virtualHosts = {
    "y.${config.custom.mainDomain}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        return = "301 https://raw.githubusercontent.com/pschmitt/yadm-init/master/init.sh";
      };
    };

    "p.${config.custom.mainDomain}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        root = pkgs.fetchFromGitHub {
          owner = "pschmitt";
          repo = "pschmitt.dev";
          rev = "b38a10206cbe16f68e959a841894097f42013006";
          hash = "sha256-w300c0c1AI2cDg5/3Gl5Q9s81skSDZox/YqLiSvWbU4=";
        };
      };
    };
  };
}
