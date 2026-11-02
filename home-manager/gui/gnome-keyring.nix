{
  config,
  pkgs,
  lib,
  ...
}:
let
  useSops = config.services.gnome-keyring.autoUnlockSops;
  useOo7 = config.host.oo7;

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
  autoUnlock = pkgs.writeShellApplication {
    name = "gnome-keyring-auto-unlock";
    runtimeInputs = [
      pkgs.systemd
      pkgs.jq
      gnome-keyring-unlock
      pkgs.libsecret
      pkgs.coreutils
    ];
    text = builtins.readFile ./scripts/gnome-keyring-auto-unlock.sh;
  };
in
{
  options.services.gnome-keyring.autoUnlockSops = lib.mkEnableOption "SOPS-backed GNOME keyring auto-unlock";

  config = {
    home.packages = lib.optional (!useOo7) gnome-keyring-unlock;

    # The keyring password lives in this host's sops file when enabled;
    # other gui hosts still use the zhj/rbw path below until migrated.
    sops.secrets = lib.mkIf useSops {
      "gnome-keyring/password".sopsFile = config.host.sopsFile;
    };

    # oo7-daemon unlocks the login keyring itself on every (re)start from this
    # credential, so a daemon restart never leaves the keyring locked and
    # the auto-unlock service+timer below are not needed.
    xdg.configFile."systemd/user/oo7-daemon.service.d/sops-credential.conf" =
      lib.mkIf (useOo7 && useSops)
        {
          text = ''
            [Unit]
            After=sops-nix.service
            Wants=sops-nix.service

            [Service]
            LoadCredential=oo7.keyring-encryption-password:${config.sops.secrets."gnome-keyring/password".path}
          '';
        };

    systemd.user = lib.mkIf (!useOo7) {
      services.gnome-keyring-auto-unlock = {
        Unit.Description = "Auto-unlock GNOME keyring";

        Service = {
          Type = "oneshot";
          ExecStart =
            if useSops then
              "${lib.getExe autoUnlock} ${lib.escapeShellArg config.sops.secrets."gnome-keyring/password".path}"
            else
              "${lib.getExe pkgs.zhj} gnome-keyring::auto-unlock --verbose --no-callback";
        };
      };

      timers.gnome-keyring-auto-unlock = {
        Unit.Description = "Auto-unlock GNOME keyring every 5 minutes";
        Timer.OnCalendar = "*:0/5"; # every 5 min
        Install.WantedBy = [ "timers.target" ];
      };
    };
  };
}
