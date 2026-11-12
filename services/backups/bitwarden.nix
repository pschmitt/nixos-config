{
  config,
  inputs,
  ...
}:

let
  # Read by systemd and handed to the units through LoadCredential, so they
  # can stay root-owned.
  secret = name: config.sops.secrets."rbw/${name}".path;
in
{
  imports = [
    inputs.rbw.nixosModules.auto
  ];

  sops.secrets = {
    "rbw/personal/password" = config.sops.mkHostSecret { };
    "rbw/personal/totp" = config.sops.mkHostSecret { };
    "rbw/personal/client-id" = config.sops.mkHostSecret { };
    "rbw/personal/client-secret" = config.sops.mkHostSecret { };
    "rbw/vaultwarden/password" = config.sops.mkHostSecret { };
    "rbw/backup/passphrase" = config.sops.mkHostSecret { };
    "rbw/backup/healthcheck-url" = config.sops.mkHostSecret { };
    "rbw/mirror/healthcheck-url" = config.sops.mkHostSecret { };
  };

  services.rbw = {
    accounts = {
      # bitwarden.com, the source of truth.
      personal = {
        email = config.mainUser.email.personal;
        passwordFile = secret "personal/password";
        totpSecretFile = secret "personal/totp";
        # bitwarden.com wants new devices registered with the personal API
        # key; rbw does that by itself when it asks.
        apiKey = {
          clientIdFile = secret "personal/client-id";
          clientSecretFile = secret "personal/client-secret";
        };
      };

      # The local Vaultwarden, which receives the one-way mirror.
      vaultwarden = {
        email = config.mainUser.email.personal;
        baseUrl = config.services.vaultwarden.config.DOMAIN;
        passwordFile = secret "vaultwarden/password";
      };
    };

    backups.personal = {
      account = "personal";
      path = "/srv/bw-backup/data";
      retentionDays = 30;
      passphraseFile = secret "backup/passphrase";
      healthcheckUrlFile = secret "backup/healthcheck-url";
      # The backup and the mirror both log into "personal": keep their
      # windows ([0,5m] and [10,15m] past the hour) apart, since bitwarden.com
      # rejects a TOTP code that was already used.
      schedule = "0/6:00:00";
      randomizedDelaySec = "5m";
    };

    # One-way mirror into the destination org's collections: "Default
    # collection" and "Anika hat ihr Passwort vergessen" are 1:1 copies of
    # the equally-named source collections; "Personal vault" has no
    # source-side counterpart and gets the source's personal vault. Copies
    # whose source entry is gone are moved to the trash, so every collection
    # stays an exact copy.
    #
    # Org membership/roles for anyone besides the destination account (e.g.
    # Anika) are set up by hand (`rbw org invite`/`rbw org confirm`).
    mirror = {
      enable = true;
      from = "personal";
      to = "vaultwarden";
      collections = {
        org = "bitwarden.com";
        fallback = "personal-vault";
        names = [
          "Personal vault"
          "Default collection"
          "Anika hat ihr Passwort vergessen"
        ];
      };
      prune = true;
      healthcheckUrlFile = secret "mirror/healthcheck-url";
      schedule = "0/6:10:00";
      randomizedDelaySec = "5m";
    };
  };

  # A hung attachment download (no network timeout) must not wedge the
  # oneshot unit forever and block its timer; fail so the next run retries
  # and Monit alerts.
  systemd.services.rbw-backup-personal.serviceConfig.TimeoutStartSec = "2h";
}
