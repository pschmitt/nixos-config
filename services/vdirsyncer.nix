{ config, ... }:
let
  syncUser = "vdirsyncer";
  syncGroup = syncUser;
  stateDir = "/var/lib/${syncUser}";
  serviceName = "vdirsyncer@google-to-nextcloud.service";
  templateDir = "vdirsyncer";
  templateName = "${templateDir}/google-to-nextcloud.conf";
  nextcloudHost = "c.${config.custom.mainDomain}";
  nextcloudUrl = "https://${nextcloudHost}/remote.php/dav/addressbooks/users/${
    config.sops.placeholder."vdirsyncer/nextcloud/username"
  }/";
  secretBase = {
    sopsFile = config.custom.sopsFile;
    restartUnits = [ serviceName ];
  };
  secretWith = extra: secretBase // extra;
  syncSecret = secretWith {
    owner = syncUser;
    group = syncGroup;
    mode = "0400";
  };
in
{
  sops.secrets = {
    "vdirsyncer/google/client-id" = secretBase;
    "vdirsyncer/google/client-secret" = secretBase;
    "vdirsyncer/google/token" = syncSecret;
    "vdirsyncer/nextcloud/username" = syncSecret;
    "vdirsyncer/nextcloud/password" = syncSecret;
  };

  sops.templates."${templateName}" = {
    owner = syncUser;
    group = syncGroup;
    mode = "0400";
    content = ''
      [general]
      status_path = "${stateDir}/google-to-nextcloud/status"

      [pair google_to_nextcloud]
      a = "google_contacts"
      b = "nextcloud_contacts"
      # collections = ["from a"]
      # sync from google's "default" address book to nextcloud's "google" address book
      collections = [["a", "default", "google"]]
      conflict_resolution = "a wins"
      # metadata = ["displayname", "color"]

      [storage google_contacts]
      type = "google_contacts"
      read_only = true
      client_id = "${config.sops.placeholder."vdirsyncer/google/client-id"}"
      client_secret = "${config.sops.placeholder."vdirsyncer/google/client-secret"}"
      # Below is what we used to let vdirsyncer write the token file itself (initial setup)
      token_file = "${stateDir}/google-to-nextcloud/google-token.json"
      # token_file = "${config.sops.placeholder."vdirsyncer/google/token"}"

      [storage nextcloud_contacts]
      type = "carddav"
      url = "${nextcloudUrl}"
      username = "${config.sops.placeholder."vdirsyncer/nextcloud/username"}"
      password = "${config.sops.placeholder."vdirsyncer/nextcloud/password"}"
    '';
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
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "900";
        Persistent = true;
      };
      configFile = config.sops.templates."${templateName}".path;
    };
  };
}
