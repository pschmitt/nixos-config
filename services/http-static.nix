{ config, pkgs, ... }:

{
  services.nginx.virtualHosts = {
    "blobs.${config.custom.mainDomain}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = false; # disabled on purpose!
      addSSL = true; # required to actually response on https requests
      root = "/mnt/data/blobs";
      locations."/" = {
        extraConfig = ''
          autoindex on;
          autoindex_localtime on;
        '';
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
          rev = "b6d5e9cc361cede2756c81e5e9ce4f34c78b3824";
          hash = "sha256-w/BOiyBQIBsxlSdMhx0jx6Q0qKWHZQti0ayfLaBjINY=";
        };
      };
    };

    "y.${config.custom.mainDomain}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        return = "301 https://raw.githubusercontent.com/pschmitt/yadm-init/main/init.sh";
      };
    };
  };
}
