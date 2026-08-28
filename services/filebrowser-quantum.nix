{ config, pkgs, ... }:
let
  port = 28170;
  externalUrl = "https://files.${config.domains.main}";
  adminUsername = config.mainUser.username;
  stateDir = "/var/lib/filebrowser-quantum";
in
{
  sops.secrets."filebrowser-quantum/admin-password" = config.custom.mkSecret {
    owner = "syncthing";
    mode = "0400";
  };

  # Rendered outside the Nix store (unlike pkgs.writeText) so the admin
  # password below is substituted with the real secret only at activation
  # time on the target host.
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
        # adminPassword) -- this is what makes the Authelia identity
        # (Remote-User: ${adminUsername}) resolve to an admin account via
        # proxy auth below, with no separate bootstrap step needed.
        adminUsername: "${adminUsername}"
        adminPassword: "${config.sops.placeholder."filebrowser-quantum/admin-password"}"
        methods:
          password:
            enabled: true
            signup: false
          proxy:
            # Trusts the Remote-User header nginx sets from Authelia's
            # authenticated session (see custom.containerServices auth.type =
            # "sso"). Only reachable at all once Authelia has already
            # authenticated the request -- see auth.publicLocations for the
            # unauthenticated /public/ share-link exception.
            enabled: true
            header: "Remote-User"
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
