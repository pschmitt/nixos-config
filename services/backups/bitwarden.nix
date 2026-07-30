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
    "bw-backup" = config.custom.mkSecret {
      owner = config.services.rbw-auto.backupUser;
      group = config.services.rbw-auto.backupGroup;
    };
    "bw-sync" = config.custom.mkSecret {
      owner = config.services.rbw-auto.syncUser;
      group = config.services.rbw-auto.syncGroup;
    };
  };

  services.rbw-auto = {
    backupJobs.personal = {
      # `environmentFiles` (the sops-managed bw-backup secret) must supply,
      # as plain KEY=value lines: BW_PASSWORD (this account's master
      # password) and, once (only needed if this account has never run
      # `rbw register` before),
      # BW_BACKUP_REGISTER_CLIENT_ID/BW_BACKUP_REGISTER_CLIENT_SECRET
      # (personal API key from https://bitwarden.com/help/article/personal-api-key/).
      account = {
        name = "personal";
        email = "philipp@schmitt.co";
      };
      backupPath = "/srv/bw-backup/data";
      environmentFiles = [ config.sops.secrets."bw-backup".path ];
      retention = 30;
      monit = {
        enable = true;
        thresholdSeconds = 86400;
      };
    };

    # `environmentFiles` (the sops-managed bw-sync secret, shared by both
    # jobs below -- same two accounts either way) must supply, as plain
    # KEY=value lines: SRC_BW_PASSWORD/DEST_BW_PASSWORD (both accounts'
    # master passwords) and, once per account that needs it,
    # SRC_/DEST_REGISTER_CLIENT_ID/_CLIENT_SECRET (same personal-API-key
    # register step as above).
    syncJobs = {
      personal = {
        sourceAccount = {
          name = "personal";
          email = "philipp@schmitt.co";
        };
        destAccount = {
          name = "vaultwarden";
          email = "philipp@schmitt.co";
          baseUrl = "https://vault.brkn.lol";
        };
        purgeDestination = true;
        environmentFiles = [ config.sops.secrets."bw-sync".path ];
        monit = {
          enable = true;
          thresholdSeconds = 86400;
        };
      };

      # Org membership/roles for anyone besides destAccount (e.g. Anika)
      # still need to be set up by hand -- `rbw org invite`/`rbw org
      # confirm`, not something this module automates.
      #
      # "Private vault" has no same-named source-side collection, so
      # bw-sync.sh gives it a full mirror of the whole source vault.
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
          baseUrl = "https://vault.brkn.lol";
        };
        mode = "collections";
        collections = {
          org = "bitwarden.com";
          names = [
            "Private vault"
            "Anika hat ihr Passwort vergessen"
            "Default collection"
          ];
        };
        environmentFiles = [ config.sops.secrets."bw-sync".path ];
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
  systemd.services = {
    "rbw-auto-sync-personal".serviceConfig.TimeoutStartSec = "2h";
    "rbw-auto-sync-collections".serviceConfig.TimeoutStartSec = "2h";
    "rbw-auto-backup-personal".serviceConfig.TimeoutStartSec = "2h";
  };
}
