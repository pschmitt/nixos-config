{
  config,
  inputs,
  ...
}:

{
  imports = [
    inputs.bw-backup.nixosModules.default
  ];

  sops.secrets = {
    "bw-backup" = config.custom.mkSecret {
      owner = config.services.bw-backup.user;
      inherit (config.services.bw-backup) group;
    };
    "bw-sync" = config.custom.mkSecret {
      owner = config.services.bw-sync.user;
      inherit (config.services.bw-sync) group;
    };
  };

  services = {
    # `environmentFiles` (sops secret "bw-backup") must supply, as plain
    # KEY=value lines: BW_PASSWORD (this account's master password) and,
    # once (only needed if this account has never run `rbw register`
    # before), BW_BACKUP_REGISTER_CLIENT_ID/BW_BACKUP_REGISTER_CLIENT_SECRET
    # (personal API key from https://bitwarden.com/help/article/personal-api-key/).
    bw-backup = {
      enable = true;
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

    # `environmentFiles` (sops secret "bw-sync") must supply, as plain
    # KEY=value lines: SRC_BW_PASSWORD/DEST_BW_PASSWORD (both accounts'
    # master passwords) and, once per account that needs it,
    # SRC_/DEST_REGISTER_CLIENT_ID/_CLIENT_SECRET (same personal-API-key
    # register step as above).
    bw-sync = {
      enable = true;
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

      # FIXME: leave disabled until the destination organization and its
      # collections actually exist on the Vaultwarden instance (org
      # membership/roles for anyone besides destAccount need to be set up
      # by hand first, e.g. `rbw org invite`/`rbw org confirm` -- this
      # module only creates the org/collections themselves, not memberships).
      # collections = {
      #   enable = true;
      #   org = "TODO";
      #   names = [ "default" "TODO" ];
      # };
    };
  };

  # A single hung `bw get attachment` download (no network timeout) can wedge
  # these oneshot units in "activating" forever, which also blocks the daily
  # timers. Fail instead so the next timer run retries and monit alerts.
  systemd.services = {
    bw-sync.serviceConfig.TimeoutStartSec = "2h";
    bw-backup.serviceConfig.TimeoutStartSec = "2h";
  };
}
