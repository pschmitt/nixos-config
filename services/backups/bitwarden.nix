{
  config,
  inputs,
  ...
}:

{
  imports = [
    inputs.rbw-auto.nixosModules.default
  ];

  sops.secrets = {
    "rbw-auto/backup" = config.custom.mkSecret {
      owner = config.services.rbw-auto.backupUser;
      group = config.services.rbw-auto.backupGroup;
    };
    "rbw-auto/sync" = config.custom.mkSecret {
      owner = config.services.rbw-auto.syncUser;
      group = config.services.rbw-auto.syncGroup;
    };
  };

  services.rbw-auto = {
    # Both the backup and sync timers log into the same "personal" account.
    # Their default 1h RandomizedDelaySec can put them within the same
    # second of each other regardless of the 10-minute stagger between
    # backupJobs.personal.schedule and syncJobs.*.period below, and Bitwarden
    # rejects a concurrent login's TOTP code as already used. Capping the
    # jitter at 5m each keeps their possible windows ([0,5m] vs [10,15m])
    # from ever overlapping.
    backupRandomizedDelaySec = "5m";
    syncRandomizedDelaySec = "5m";

    backupJobs.personal = {
      # `environmentFiles` (the sops-managed rbw-auto/backup secret) must
      # supply, as plain KEY=value lines: BW_PASSWORD (this account's master
      # password) and, once (only needed if this account has never run
      # `rbw register` before),
      # BW_BACKUP_REGISTER_CLIENT_ID/BW_BACKUP_REGISTER_CLIENT_SECRET
      # (personal API key from https://bitwarden.com/help/article/personal-api-key/).
      account = {
        name = "personal";
        email = "philipp@schmitt.co";
      };
      backupPath = "/srv/bw-backup/data";
      environmentFiles = [ config.sops.secrets."rbw-auto/backup".path ];
      retention = 30;
      schedule = "0/6:00:00";
      monit = {
        enable = true;
        thresholdSeconds = 86400;
      };
    };

    # `environmentFiles` (the sops-managed rbw-auto/sync secret, shared by
    # both jobs below -- same two accounts either way) must supply, as
    # plain KEY=value lines: SRC_BW_PASSWORD/DEST_BW_PASSWORD (both
    # accounts' master passwords) and, once per account that needs it,
    # SRC_/DEST_REGISTER_CLIENT_ID/_CLIENT_SECRET (same personal-API-key
    # register step as above).
    syncJobs = {
      # "Personal vault" has no same-named source-side collection, so
      # bw-sync.sh gives it a full mirror of the whole source vault -- into
      # the "bitwarden.com" org's "Personal vault" collection rather than
      # destAccount's own bare personal vault.
      personal = {
        sourceAccount = {
          name = "personal";
          email = "philipp@schmitt.co";
        };
        destAccount = {
          name = "vaultwarden";
          email = "philipp@schmitt.co";
          baseUrl = config.services.vaultwarden.config.DOMAIN;
        };
        mode = "collections";
        collections = {
          org = "bitwarden.com";
          names = [ "Personal vault" ];
        };
        environmentFiles = [ config.sops.secrets."rbw-auto/sync".path ];
        # Offset from backupJobs.personal's "0/6:00:00" schedule: both jobs
        # log into the same "personal" account, and a same-second collision
        # made Bitwarden reject one job's TOTP code as already used.
        period = "0/6:10:00";
        monit = {
          enable = true;
          thresholdSeconds = 86400;
        };
      };

      # Org membership/roles for anyone besides destAccount (e.g. Anika)
      # still need to be set up by hand -- `rbw org invite`/`rbw org
      # confirm`, not something this module automates.
      #
      # "Anika hat ihr Passwort vergessen" and "Default collection" are
      # 1:1 mirrors of the equally-named collections that already exist
      # in the source (personal) account.
      collections = {
        sourceAccount = {
          name = "personal";
          email = "philipp@schmitt.co";
        };
        destAccount = {
          name = "vaultwarden";
          email = "philipp@schmitt.co";
          baseUrl = config.services.vaultwarden.config.DOMAIN;
        };
        mode = "collections";
        collections = {
          org = "bitwarden.com";
          names = [
            "Default collection"
            "Anika hat ihr Passwort vergessen"
          ];
        };
        environmentFiles = [ config.sops.secrets."rbw-auto/sync".path ];
        period = "0/6:10:00";
        monit = {
          enable = true;
          thresholdSeconds = 86400;
        };
      };
    };
  };

  # A single hung `bw get attachment` download (no network timeout) can wedge
  # these oneshot units in "activating" forever, which also blocks the daily
  # timers. Fail instead so the next timer run retries and monit alerts.
  systemd.services."rbw-auto-sync".serviceConfig.TimeoutStartSec = "2h";
  systemd.services."rbw-auto-backup-personal".serviceConfig.TimeoutStartSec = "2h";
}
