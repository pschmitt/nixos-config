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
          rev = "35f63e78171ea9775572c57d7849681b1ffbabe4";
          hash = "sha256-n7EA/v9lKTEFCbPJNG3iSp6u8XJ7KNu//FI0wH6ieu8=";
        };
      };
    };
  };
}
