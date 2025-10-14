{
  config,
  lib,
  pkgs,
  ...
}:
let
  syncUser = "vdirsyncer";
  syncGroup = syncUser;
  stateDir = "/var/lib/${syncUser}";
  nextcloudHost = "c.${config.custom.mainDomain}";
  nextcloudRootUrl = "https://${nextcloudHost}/remote.php/dav/addressbooks/users/${
    config.sops.placeholder."vdirsyncer/nextcloud/username"
  }/";
in
{
  sops.secrets = {
    "vdirsyncer/google/client-id" = {
      sopsFile = config.custom.sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/google/client-secret" = {
      sopsFile = config.custom.sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/google/token" = {
      sopsFile = config.custom.sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/nextcloud/username" = {
      sopsFile = config.custom.sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/nextcloud/password" = {
      sopsFile = config.custom.sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
  };

  users.groups.${syncGroup} = { };
  users.users.${syncUser} = {
    isSystemUser = true;
    group = syncGroup;
    home = stateDir;
    createHome = true;
  };

  services.vdirsyncer = {
    enable = true;

    jobs.google-to-nextcloud = {
      enable = true;
      user = syncUser;
      group = syncGroup;
      forceDiscover = true;

      config = {
        general.status_path = "${stateDir}/google-to-nextcloud/status";

        storages = {
          google_contacts = {
            type = "google_contacts";
            read_only = true;
            "client_id.fetch" = [
              "command"
              "cat"
              config.sops.secrets."vdirsyncer/google/client-id".path
            ];
            "client_secret.fetch" = [
              "command"
              "cat"
              config.sops.secrets."vdirsyncer/google/client-secret".path
            ];
            token_file = "${stateDir}/google-to-nextcloud/google-token.json";
          };

          nextcloud_contacts = {
            type = "carddav";
            url = nextcloudRootUrl;
            "username.fetch" = [
              "command"
              "cat"
              config.sops.secrets."vdirsyncer/nextcloud/username".path
            ];
            "password.fetch" = [
              "command"
              "cat"
              config.sops.secrets."vdirsyncer/nextcloud/password".path
            ];
          };
        };

        pairs.google_to_nextcloud = {
          a = "google_contacts";
          b = "nextcloud_contacts";
          collections = [
            [
              "google_sync"
              "default"
              "google"
            ]
          ];
          conflict_resolution = "a wins";
          metadata = [
            "displayname"
            "color"
          ];
        };
      };

      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "900";
        Persistent = true;
      };
    };
  };

  # Just delete the state before every run, this allows us to delete
  # the "google" address book from nextcloud cleanly if we ever want to.
  systemd.services."vdirsyncer@google-to-nextcloud".serviceConfig.ExecStartPre = lib.mkAfter [
    (pkgs.writeShellScript "vdirsyncer-rm-status-google-to-nextcloud" ''
      ${pkgs.coreutils}/bin/rm -rf -- \
        "${stateDir}/google-to-nextcloud/google_to_nextcloud" \
        "${stateDir}/google-to-nextcloud/google_to_nextcloud.collections"
    '')
  ];
}
