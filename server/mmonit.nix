{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [ mmonit ];
  systemd.packages = [ pkgs.mmonit ];
  systemd.services.mmonit.wantedBy = lib.mkForce [ "multi-user.target" ];

  users.users.mmonit = {
    isSystemUser = true;
    home = "/var/lib/mmonit";
    createHome = true;
    group = "mmonit";
  };
  users.groups.mmonit = { };

  # license
  sops.secrets."mmonit/license" = {
    sopsFile = config.custom.sopsFile;
    owner = "mmonit";
  };

  environment.etc."mmonit/license.xml".source = "${config.sops.secrets."mmonit/license".path}";

  services.restic.backups.main.paths = lib.mkAfter (
    config.services.restic.backups.main.paths ++ [ "/var/lib/mmonit" ]
  );

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts =
      let
        commonConfig = {
          # NOTE we do HTTP-01 here!
          enableACME = true;
          forceSSL = true;

          locations."/" = {
            proxyPass = "http://127.0.0.1:8080/";
            index = "index.csp";
            proxyWebsockets = true;
            extraConfig = ''
              # Avoid redirections to the wrong port (ie. 8080)
              proxy_set_header X-Forwarded-Port $server_port;
            '';
          };
        };
      in
      {
        "mmonit.${config.networking.hostName}.${config.custom.mainDomain}" = commonConfig;
        "mmonit.${config.custom.mainDomain}" = commonConfig;
      };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = config.custom.email;
  };
}
