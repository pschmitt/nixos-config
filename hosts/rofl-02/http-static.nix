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
          rev = "b25cca97e792c7fcd02bf51a649ea8a60bc581e5";
          hash = "sha256-XrzyBdzVsNtua1A1h6iErAj1MBjhWyrHNtXihbV1fco=";
        };
      };
    };
  };
}
