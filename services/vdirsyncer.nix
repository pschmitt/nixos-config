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
  # hook, but every DAV write funnels through DAVStorage._put, so this
  # patches just that one method to fix the one known-bad pattern before
  # the PUT is sent.
  #
  # Delivered as a PYTHONPATH-injected sitecustomize.py, auto-imported by
  # the interpreter at startup -- but at that exact point `vdirsyncer` and
  # its dependencies aren't on sys.path yet (the venv wrapper's own
  # site.addsitedir() calls, which add them, run *after* sitecustomize).
  # So this can't just eagerly `from vdirsyncer.storage import dav`, and
  # instead registers a sys.meta_path post-import hook that applies the
  # patch lazily, whenever something later actually imports
  # vdirsyncer.storage.dav (by which point sys.path is fully populated).
  vdirsyncerDavSanitizeShim = pkgs.runCommand "vdirsyncer-dav-sanitize-shim" { } ''
    mkdir -p $out
    cat > $out/sitecustomize.py <<'EOF'
    import sys
    from importlib.abc import MetaPathFinder
    from importlib.util import find_spec


    def _patch_dav(dav):
        import re

        from vdirsyncer.vobject import Item

        fix = re.compile(r"(;VALUE=DATE),(X-APPLE-OMIT-YEAR=)", re.IGNORECASE)
        orig_put = dav.DAVStorage._put

        async def sanitizing_put(self, href, item, etag):
            fixed = fix.sub(r"\1;\2", item.raw)
            if fixed != item.raw:
                item = Item(fixed)
            return await orig_put(self, href, item, etag)

        dav.DAVStorage._put = sanitizing_put


    class _DavPatchFinder(MetaPathFinder):
        def find_spec(self, fullname, path, target=None):
            if fullname != "vdirsyncer.storage.dav":
                return None
            sys.meta_path.remove(self)
            try:
                spec = find_spec(fullname)
            finally:
                sys.meta_path.insert(0, self)
            if spec is None or spec.loader is None:
                return None
            orig_exec_module = spec.loader.exec_module

            def exec_module(module):
                orig_exec_module(module)
                _patch_dav(module)

            spec.loader.exec_module = exec_module
            return spec


    try:
        sys.meta_path.insert(0, _DavPatchFinder())
    except Exception:
        pass
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
