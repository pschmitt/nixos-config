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
  sops.secrets."forgejo/runner/token" = {
    inherit (config.custom) sopsFile;
    # FIXME The gitea-runner is dynamic. It won't exist at build time.
    # owner = "gitea-runner";
  };

  # FIXME Patch the service to load the token from a file
  # https://dee.underscore.world/blog/systemd-credentials-nixos-containers/
  systemd.services.gitea-runner-main = {
    serviceConfig = {
      LoadCredential = [ "token:${config.sops.secrets."forgejo/runner/token".path}" ];
      Environment = [ "TOKEN=%d/token" ];
    };
  };

  # Explicitly allow ssh
  networking.firewall.allowedTCPPorts = lib.mkBefore [ 22 ];

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
      dump.enable = true;
      stateDir = "/srv/forgejo";
    };

    gitea-actions-runner.instances.main = {
      # TODO Enable once we figure out how to feed the credentials to the runner
      # The service uses DynamicUser=true
      # This looks like the way to go:
      # https://github.com/Mic92/sops-nix/issues/198
      enable = false;
      name = config.networking.hostName;
      url = config.services.forgejo.settings.server.ROOT_URL;
      # FIXME See comment above about DynamicUser
      # tokenFile = config.sops.secrets."forgejo/runner/token".path;
      tokenFile = "/dev/null";
      labels = [ config.networking.hostName ];
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
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
