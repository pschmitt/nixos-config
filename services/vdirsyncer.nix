{
  config,
  lib,
  ...
}:
let
  syncUser = "vdirsyncer";
  syncGroup = syncUser;
  stateDir = "/var/lib/${syncUser}";
  gcontactsStateDir = "${stateDir}/google-contacts";
  fsDir = "${gcontactsStateDir}/data";

  nextcloudHost = "c.${config.domains.main}";
  nextcloudRootUrl = "https://${nextcloudHost}/remote.php/dav/addressbooks/users/${
    config.sops.placeholder."vdirsyncer/nextcloud/username"
  }/";
in
{
  sops.secrets = {
    "vdirsyncer/google/client-id" = {
      inherit (config.custom) sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/google/client-secret" = {
      inherit (config.custom) sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/google/token" = {
      inherit (config.custom) sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/nextcloud/username" = {
      inherit (config.custom) sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/nextcloud/password" = {
      inherit (config.custom) sopsFile;
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
  };

  users = {
    groups.${syncGroup} = { };
    users.${syncUser} = {
      isSystemUser = true;
      group = syncGroup;
      home = stateDir;
      createHome = true;
    };
  };

  services.vdirsyncer = {
    enable = true;

    jobs.google-contacts = {
      enable = true;
      user = syncUser;
      group = syncGroup;
      forceDiscover = true;

      config = {
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
            token_file = "${stateDir}/google-contacts/google-token.json";
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

          filesystem_contacts = {
            type = "filesystem";
            path = fsDir;
            fileext = ".vcf";
          };
        };

        pairs = {
          google_contacts_to_nextcloud = {
            a = "google_contacts";
            b = "nextcloud_contacts";
            collections = [
              # TODO shouldn't this be ["a", "default", "google"]?
              [
                "google_sync"
                "default"
                "google"
              ]
            ];
            conflict_resolution = "a wins";
            metadata = [
              "color"
              "displayname"
            ];
          };

          google_contacts_to_fs = {
            a = "google_contacts";
            b = "filesystem_contacts";
            collections = [ "default" ];
            conflict_resolution = "a wins";
            metadata = [
              "color"
              "displayname"
            ];
          };
        };
      };

      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "900";
        Persistent = true;
      };
    };
  };

  users.users."${config.mainUser.username}" = {
    extraGroups = lib.mkAfter [ "${syncGroup}" ];
  };

  # system.activationScripts.vdirsyncerAcls.text = ''
  #   ${pkgs.acl}/bin/setfacl -m u:pschmitt:rx /var/lib/vdirsyncer
  #   ${pkgs.acl}/bin/setfacl -m u:pschmitt:rx /var/lib/vdirsyncer/google-contacts
  # '';

  # Just delete the state before every run, this allows us to delete
  # the "google" address book from nextcloud cleanly if we ever want to.
  # systemd.services."vdirsyncer@google-contacts".serviceConfig.ExecStartPre = lib.mkAfter (
  #   let
  #     pairNames = builtins.attrNames config.services.vdirsyncer.jobs."google-contacts".config.pairs;
  #
  #     rmTargets = builtins.concatLists (
  #       map (p: [
  #         "${gcontactsStateDir}/${p}"
  #         "${gcontactsStateDir}/${p}.collections"
  #       ]) pairNames
  #     );
  #
  #     rmStatus = pkgs.writeShellScript "vdirsyncer-rm-status-google-contacts" ''
  #       rm -rf -- ${lib.escapeShellArgs rmTargets}
  #     '';
  #   in
  #   [ rmStatus ]
  # );
}
