{
  config,
  lib,
  pkgs,
  ...
}:
let
  forgejoHostName = "git.${config.domains.main}";
in
{
  # Explicitly allow ssh
  networking.firewall.allowedTCPPorts = lib.mkBefore [ 22 ];

  # Fix permissions after UID changes (e.g., after reinstall)
  systemd.tmpfiles.rules = [
    "Z ${config.services.forgejo.stateDir} 0750 ${config.services.forgejo.user} ${config.services.forgejo.group} - -"
  ];

  services = {
    forgejo = {
      enable = true;
      settings = {
        server = {
          DOMAIN = forgejoHostName;
          ROOT_URL = "https://${forgejoHostName}";
          SSH_PORT = 22; # this ain't a container :)
        };
        service = {
          DISABLE_REGISTRATION = true;
        };
      };
      lfs.enable = true;
      dump = {
        enable = true;
        age = "10d";
      };
      stateDir = "/srv/forgejo";
    };

    nginx =
      let
        hostNames = [ config.services.forgejo.settings.server.DOMAIN ];
        virtualHosts = builtins.listToAttrs (
          map (hostName: {
            name = hostName;
            value = {
              enableACME = true;
              # FIXME https://github.com/NixOS/nixpkgs/issues/210807
              acmeRoot = null;
              forceSSL = true;
              locations."/" = {
                proxyPass = "http://${config.services.forgejo.settings.server.HTTP_ADDR}:${toString config.services.forgejo.settings.server.HTTP_PORT}";
                recommendedProxySettings = true;
                proxyWebsockets = true;
                # Allow uploading large files
                extraConfig = ''
                  client_max_body_size 50000M;
                '';
              };
            };
          }) hostNames
        );
      in
      {
        inherit virtualHosts;
      };
  };

  services.monit.config = lib.mkAfter ''
    check host "forgejo" with address "${config.services.forgejo.settings.server.HTTP_ADDR}"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart forgejo.service"
      if failed
        port ${toString config.services.forgejo.settings.server.HTTP_PORT}
        protocol http
        with timeout 15 seconds
        for 3 cycles
      then restart
      if 3 restarts within 15 cycles then alert
  '';
}
