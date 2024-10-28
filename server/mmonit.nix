{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [ mmonit ];
  systemd.packages = [ pkgs.mmonit ];
  # FIXME The eternal NixOS question: how to enable a systemd service?!
  systemd.services.mmonit.enable = true;
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
        "mmonit.oci-03.brkn.lol" = commonConfig;
        "mmonit.brkn.lol" = commonConfig;
        "mmonit.oci-03.heimat.dev" = commonConfig;
        "mmonit.heimat.dev" = commonConfig;
      };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = config.custom.email;
  };
}
