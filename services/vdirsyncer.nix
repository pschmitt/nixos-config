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
  gcontactsStateDir = "${stateDir}/google-contacts";
  fsDir = "${gcontactsStateDir}/data";

  nextcloudHost = "c.${config.domains.main}";
  nextcloudRootUrl = "https://${nextcloudHost}/remote.php/dav/addressbooks/users/${
    config.sops.placeholder."vdirsyncer/nextcloud/username"
  }/";

  # Google's CardDAV export renders BDAY's parameter list for contacts with
  # a year-omitted birthday (originally from Apple/iCloud) as
  # `VALUE=DATE,X-APPLE-OMIT-YEAR=...` -- a comma joining two distinct
  # parameters instead of the required semicolon. Nextcloud's bundled
  # sabre/vobject parses that comma as one multi-valued VALUE parameter and
  # crashes with "TypeError: strtoupper(): ... array given" on PUT, failing
  # the whole contact (and the sync run). vdirsyncer has no item-transform
  # hook, but every DAV write funnels through DAVStorage._put, so a
  # PYTHONPATH-injected sitecustomize.py (auto-imported by the interpreter
  # at startup) can patch just that one method to fix the one known-bad
  # pattern before the PUT is sent.
  vdirsyncerDavSanitizeShim = pkgs.runCommand "vdirsyncer-dav-sanitize-shim" { } ''
    mkdir -p $out
    cat > $out/sitecustomize.py <<'EOF'
    import re

    from vdirsyncer.storage import dav
    from vdirsyncer.vobject import Item

    _BDAY_PARAM_FIX = re.compile(r"(;VALUE=DATE),(X-APPLE-OMIT-YEAR=)", re.IGNORECASE)

    _orig_put = dav.DAVStorage._put


    async def _sanitizing_put(self, href, item, etag):
        fixed = _BDAY_PARAM_FIX.sub(r"\1;\2", item.raw)
        if fixed != item.raw:
            item = Item(fixed)
        return await _orig_put(self, href, item, etag)


    dav.DAVStorage._put = _sanitizing_put
    EOF
  '';
in
{
  sops.secrets = {
    "vdirsyncer/google/client-id" = config.custom.mkSecret {
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/google/client-secret" = config.custom.mkSecret {
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/google/token" = config.custom.mkSecret {
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/nextcloud/username" = config.custom.mkSecret {
      owner = syncUser;
      group = syncGroup;
      mode = "0400";
    };
    "vdirsyncer/nextcloud/password" = config.custom.mkSecret {
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

  systemd.services."vdirsyncer@google-contacts".environment.PYTHONPATH = vdirsyncerDavSanitizeShim;

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
