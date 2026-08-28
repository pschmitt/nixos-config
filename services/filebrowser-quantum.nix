{ config, pkgs, ... }:
let
  port = 28170;
  externalUrl = "https://files.${config.domains.main}";
  autheliaIssuerUrl = "https://auth.${config.domains.main}";
  adminUsername = config.mainUser.username;
  stateDir = "/var/lib/filebrowser-quantum";
in
{
  sops.secrets = {
    "filebrowser-quantum/admin-password" = config.custom.mkSecret {
      owner = "syncthing";
      mode = "0400";
    };
    "filebrowser-quantum/oidc-client-secret" = config.custom.mkSecret {
      owner = "syncthing";
      mode = "0400";
    };
  };

  # Rendered outside the Nix store (unlike pkgs.writeText) so the secrets
  # below are substituted with their real values only at activation time on
  # the target host.
  sops.templates."filebrowser-quantum/config.yaml" = {
    content = ''
      server:
        listen: "127.0.0.1"
        port: ${toString port}
        externalUrl: "${externalUrl}"
        database: "${stateDir}/filebrowser.sqlite"
        cacheDir: "${stateDir}/cache"
        sources:
          - path: "${config.custom.syncthing.documentsDir}"
            name: "Documents"
          - path: "${config.custom.syncthing.folders.music.dir}"
            name: "Music"
          - path: "${config.custom.syncthing.folders.pictures.dir}"
            name: "Pictures"
          - path: "${config.custom.syncthing.folders.backups.dir}"
            name: "Backups"
      http:
        trustedHeaders:
          - "X-Forwarded-For"
      auth:
        # Set on every boot (backend/cmd/user.go: any existing user matching
        # adminUsername gets promoted to admin and its password reset to
        # adminPassword). Logging in via OIDC as this same Authelia username
        # resolves to this same admin account -- and adminGroup below does
        # the same for anyone else in Authelia's "admin" group.
        adminUsername: "${adminUsername}"
        adminPassword: "${config.sops.placeholder."filebrowser-quantum/admin-password"}"
        methods:
          password:
            # Kept as a local fallback login; not used day-to-day.
            enabled: true
            signup: false
          oidc:
            # Real OIDC login against Authelia (client registered in
            # services/authelia.nix's oidc.yml template) -- FileBrowser
            # Quantum handles its own login/redirect flow end-to-end, so
            # this service is NOT behind nginx's Authelia auth_request gate
            # (see hosts/rofl-10/container-services.nix). Public share links
            # under /public/ are unaffected either way.
            enabled: true
            adminGroup: "admin"
            clientId: "filebrowser-quantum"
            clientSecret: "${config.sops.placeholder."filebrowser-quantum/oidc-client-secret"}"
            issuerUrl: "${autheliaIssuerUrl}"
            scopes: "openid email profile groups"
    '';
    owner = "syncthing";
    group = "syncthing";
    mode = "0400";
    restartUnits = [ "filebrowser-quantum.service" ];
  };

  systemd.services.filebrowser-quantum = {
    description = "FileBrowser Quantum";
    documentation = [ "https://github.com/gtsteffaniak/filebrowser" ];
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      # Runs as the syncthing user/group so it shares read-write ownership of
      # the synced tree without touching that module's directory perms.
      User = "syncthing";
      Group = "syncthing";
      # FileBrowser Quantum's -c flag also scans its config file's directory
      # for extra yaml files to merge, which needs list (r), not just
      # traversal (x), on /run/secrets/rendered/filebrowser-quantum -- that
      # directory only grants "other" execute, so join its owning group.
      SupplementaryGroups = [ "keys" ];
      StateDirectory = "filebrowser-quantum";
      WorkingDirectory = stateDir;
      ExecStart = "${pkgs.filebrowser-quantum}/bin/filebrowser-quantum -c ${
        config.sops.templates."filebrowser-quantum/config.yaml".path
      }";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
