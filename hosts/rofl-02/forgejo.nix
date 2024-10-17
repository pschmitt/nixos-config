{ config, ... }:
let
  forgejoHostName = "git2.${config.custom.mainDomain}";
in
{
  sops.secrets."forgejo/runner/token" = {
    sopsFile = config.custom.sopsFile;
    # FIXME The gitea-runner is dynamic. It won't exit at build time.
    # owner = "gitea-runner";
  };

  services = {
    forgejo = {
      enable = true;
      settings = {
        server = {
          DOMAIN = forgejoHostName;
          ROOT_URL = "https://${forgejoHostName}";
          SSH_PORT = 12222;
        };
        service = {
          DISABLE_REGISTRATION = true;
        };
      };
      lfs.enable = true;
      dump.enable = true;
      stateDir = "/srv/forgejo";
    };

    gitea-actions-runner.instances.main-runner = {
      # TODO Enable once we figure out how to feed the credentials to the runner
      # The service uses DynamicUser=true
      # https://github.com/Mic92/sops-nix/issues/198
      # This looks like the way to go:
      # https://dee.underscore.world/blog/systemd-credentials-nixos-containers/
      enable = false;
      name = config.networking.hostName;
      url = config.services.forgejo.settings.server.ROOT_URL;
      # FIXME See comment above about DynamicUser
      tokenFile = config.sops.secrets."forgejo/runner/token".path;
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
        virtualHosts = virtualHosts;
      };
  };
}
