{ config, lib, pkgs, ... }: {
  environment.systemPackages = with pkgs; [ mmonit ];
  systemd.packages = [ pkgs.mmonit ];
  systemd.services.mmonit.enable = true;

  users.users.mmonit = {
    isSystemUser = true;
    home = "/var/lib/mmonit";
    createHome = true;
    group = "mmonit";
  };
  users.groups.mmonit = { };

  # license
  age.secrets.mmonit-license.file = ../secrets/mmonit-license.age;
  environment.etc."mmonit/license.xml".source = "${config.age.secrets.mmonit-license.path}";

  services.restic.backups.main.paths = lib.mkAfter (config.services.restic.backups.main.paths ++ [
    "/var/lib/mmonit"
  ]);

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."mmonit.oci-03.heimat.dev" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://localhost:8080/";
        index = "index.csp";
        proxyWebsockets = true;
        extraConfig = ''
          # Avoid redirections to the wrong port (ie. 8080)
          proxy_set_header X-Forwarded-Port $server_port;
        '';
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = config.custom.email;
  };
}
