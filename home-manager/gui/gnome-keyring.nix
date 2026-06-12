{
  config,
  pkgs,
  lib,
  hostname,
  ...
}:
let
  # Hosts whose keyring password lives in sops (vs the legacy zhj/rbw path).
  keyringSopsHosts = [
    "ge2"
    "x13"
  ];
  useSops = builtins.elem hostname keyringSopsHosts;

  gnome-keyring-unlock = pkgs.stdenvNoCC.mkDerivation {
    pname = "gnome-keyring-unlock";
    version = "cd3eb79";
    src = pkgs.fetchFromGitea {
      domain = "codeberg.org";
      owner = "umglurf";
      repo = "gnome-keyring-unlock";
      rev = "cd3eb799ead710b930871224423a88f2d186cbea";
      hash = "sha256-zVp+1TZZ2E7qwmcN1kgZZyhjgi407hIlv3y4zWundvY=";
    };
    nativeBuildInputs = [ pkgs.python3 ];
    dontBuild = true;
    installPhase = ''
      install -Dm755 unlock.py $out/bin/gnome-keyring-unlock
    '';
    postPatch = "patchShebangs unlock.py";
  };

  # sops-backed replacement for the zhj `gnome-keyring::auto-unlock` (which
  # pulled the password from rbw). Reads the password from a sops secret and
  # unlocks the login keyring; no-ops if already unlocked or no secret present.
  autoUnlock = pkgs.writeShellScript "gnome-keyring-auto-unlock" ''
    set -uo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.systemd # busctl
        pkgs.jq
        gnome-keyring-unlock
        pkgs.libsecret # secret-tool
        pkgs.coreutils
      ]
    }:$PATH

    secret_file="${config.sops.secrets."gnome-keyring/password".path}"

    keyring_locked() {
      local coll
      for coll in $(busctl -j --user --no-pager get-property \
        org.freedesktop.secrets /org/freedesktop/secrets \
        org.freedesktop.Secret.Service Collections 2>/dev/null | jq -er '.data[]' 2>/dev/null)
      do
        if busctl -j --user --no-pager get-property \
          org.freedesktop.secrets "$coll" \
          org.freedesktop.Secret.Collection Locked 2>/dev/null | jq -e '.data' >/dev/null 2>&1
        then
          return 0 # at least one collection is locked
        fi
      done
      return 1
    }

    if ! keyring_locked
    then
      echo "Keyring already unlocked"
      exit 0
    fi

    if [[ ! -r "$secret_file" ]]
    then
      echo "No keyring password secret at $secret_file, skipping" >&2
      exit 0
    fi

    # gnome-keyring-unlock reads the password from stdin (no trailing newline).
    printf '%s' "$(< "$secret_file")" | gnome-keyring-unlock

    # Touching a secret forces the (now unlocked) login keyring to settle.
    date -Iseconds | secret-tool store --label="gnome-keyring-auto-unlock" \
      app gnome-keyring-auto-unlock test unlock 2>/dev/null || true
    secret-tool clear app gnome-keyring-auto-unlock test unlock 2>/dev/null || true

    if keyring_locked
    then
      echo "Failed to unlock keyring" >&2
      exit 1
    fi
  '';
in
{
  home.packages = [ gnome-keyring-unlock ];

  # The keyring password lives in this host's sops file (keyringSopsHosts);
  # other gui hosts still use the zhj/rbw path below until migrated.
  sops.secrets = lib.mkIf useSops {
    "gnome-keyring/password".sopsFile = config.host.sopsFile;
  };

  systemd.user.services.gnome-keyring-auto-unlock = {
    Unit.Description = "Auto-unlock GNOME keyring";

    Service = {
      Type = "oneshot";
      ExecStart =
        if useSops then
          "${autoUnlock}"
        else
          "${config.home.homeDirectory}/bin/zhj gnome-keyring::auto-unlock --verbose --no-callback";
    };
  };

  systemd.user.timers.gnome-keyring-auto-unlock = {
    Unit.Description = "Auto-unlock GNOME keyring every 5 minutes";
    Timer.OnCalendar = "*:0/5"; # every 5 min
    Install.WantedBy = [ "timers.target" ];
  };
}
