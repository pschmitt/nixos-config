{
  config,
  pkgs,
  lib,
  ...
}:
let
  psqlDir = "/mnt/data/srv/postgresql";
in
{
  # NOTE Do we really need this? Isn't the module crearing the dir already?
  # NOTE The postgres user's home gets set to services.postgresql.dataDir
  systemd.tmpfiles.rules = [
    "d  ${psqlDir}  0755 ${toString config.users.users.postgres.uid} ${toString config.users.groups.postgres.gid} - -"

    # symlink
    "L+ /var/lib/postgresql       -    -  -  - ${psqlDir}"
  ];

  services = {
    postgresql = {
      package = pkgs.postgresql_17;
      dataDir = "${psqlDir}/${config.services.postgresql.package.psqlSchema}";
    };

    postgresqlBackup = {
      enable = true;
      backupAll = true;
      location = "${psqlDir}/backups";
      startAt = "*-*-* 02:00:00"; # Daily at 2 AM
      compression = "gzip";
    };
  };

  # FIXME This only *kinda* works
  # https://nixos.org/manual/nixos/stable/#module-services-postgres-upgrading
  environment.systemPackages = [
    (
      let
        # XXX specify the postgresql package you'd like to upgrade to.
        # Do not forget to list the extensions you need.
        # newPostgres = pkgs.postgresql_17.withPackages (pp: [
        #   # immich used to use pgvecto-rs
        #   # pp.pgvecto-rs
        #   pp.pgvector
        #   pp.vectorchord
        # ]);
        newPostgres = pkgs.postgresql_17.withPackages config.services.postgresql.extensions;
        cfg = config.services.postgresql;
      in
      pkgs.writeScriptBin "upgrade-pg-cluster" ''
        set -eux
        # XXX it's perhaps advisable to stop all services that depend on postgresql
        systemctl stop postgresql

        export NEWDATA="/var/lib/postgresql/${newPostgres.psqlSchema}"
        export NEWBIN="${newPostgres}/bin"

        export OLDDATA="${cfg.dataDir}"
        export OLDBIN="${cfg.finalPackage}/bin"

        install -d -m 0700 \
          -o "${toString config.users.users.postgres.uid}" \
          -g "${toString config.users.groups.postgres.gid}" \
          "$NEWDATA"

        cd "$NEWDATA"
        sudo -u postgres "$NEWBIN/initdb" -D "$NEWDATA" ${lib.escapeShellArgs cfg.initdbArgs}

        sudo -u postgres "$NEWBIN/pg_upgrade" \
          --old-datadir "$OLDDATA" --new-datadir "$NEWDATA" \
          --old-bindir "$OLDBIN" --new-bindir "$NEWBIN" \
          --new-options "-c shared_preload_libraries='vchord.so'" \
          "$@"
      ''
    )
  ];

  services.monit.config = lib.mkAfter ''
    check program "postgresql" with path "${config.services.postgresql.package}/bin/pg_isready -q"
      group database
      restart program = "${pkgs.systemd}/bin/systemctl restart postgresql.service"
      if status > 0 then restart
      if 5 restarts within 10 cycles then alert
  '';
}
