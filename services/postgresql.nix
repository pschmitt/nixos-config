{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Stick to psql 15 for now
  # TODO upgrade to 16!
  services.postgresql.package = pkgs.postgresql_15;

  # FIXME This only *kinda* works
  # https://nixos.org/manual/nixos/stable/#module-services-postgres-upgrading
  environment.systemPackages = [
    (
      let
        # XXX specify the postgresql package you'd like to upgrade to.
        # Do not forget to list the extensions you need.
        oldPostgres = pkgs.postgresql_15.withPackages (pp: [
          pp.pgvector
          pp.pgvecto-rs
        ]);

        cfg = config.services.postgresql;
      in
      pkgs.writeScriptBin "upgrade-pg-cluster" ''
        set -eux
        # XXX it's perhaps advisable to stop all services that depend on postgresql
        systemctl stop postgresql

        export OLDDATA="/var/lib/postgresql/${oldPostgres.psqlSchema}"
        export OLDBIN="${oldPostgres}/bin"

        export NEWDATA="${cfg.dataDir}"
        export NEWBIN="${cfg.finalPackage}/bin"

        install -d -m 0700 -o postgres -g postgres "$NEWDATA"
        cd "$NEWDATA"
        sudo -u postgres "$NEWBIN/initdb" -D "$NEWDATA" ${lib.escapeShellArgs cfg.initdbArgs}

        sudo -u postgres "$NEWBIN/pg_upgrade" \
          --old-datadir "$OLDDATA" --new-datadir "$NEWDATA" \
          --old-bindir "$OLDBIN" --new-bindir "$NEWBIN" \
          "$@"
      ''
    )
  ];
}
