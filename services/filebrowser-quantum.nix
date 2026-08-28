{ config, pkgs, ... }:
let
  port = 28170;
  externalUrl = "https://files.${config.domains.main}";
  adminUsername = config.mainUser.username;
  stateDir = "/var/lib/filebrowser-quantum";

  configFile = pkgs.writeText "filebrowser-quantum-config.yaml" ''
    server:
      sources:
        - path: "${config.custom.syncthing.documentsDir}"
          name: "Documents"
      database:
        path: "${stateDir}/filebrowser.sqlite"
      cacheDir: "${stateDir}/cache"
    http:
      listen: "127.0.0.1"
      port: ${toString port}
      externalUrl: "${externalUrl}"
      trustProxyHeaders: true
    auth:
      adminUsername: "${adminUsername}"
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

  # Bootstraps/refreshes the admin account on every start so the Authelia
  # identity (Remote-User: ${adminUsername}) resolves to an existing admin
  # user via proxy auth, rather than being auto-provisioned as a plain user.
  # `user set` is create-or-update, so this is safe to (re)run on every start.
  bootstrapAdmin = pkgs.writeShellScript "filebrowser-quantum-bootstrap-admin" ''
    set -euo pipefail
    ${pkgs.filebrowser-quantum}/bin/filebrowser-quantum \
      -c ${configFile} \
      user set ${adminUsername} --admin --password \
      < ${config.sops.secrets."filebrowser-quantum/admin-password".path}
  '';
in
{
  sops.secrets."filebrowser-quantum/admin-password" = config.custom.mkSecret {
    owner = "syncthing";
    mode = "0400";
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
      StateDirectory = "filebrowser-quantum";
      WorkingDirectory = stateDir;
      ExecStartPre = "${bootstrapAdmin}";
      ExecStart = "${pkgs.filebrowser-quantum}/bin/filebrowser-quantum -c ${configFile}";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
