{ config, pkgs, ... }:
{
  home.packages = [
    # usage: gnome-keyring-unlock <<< PASSWORD
    (pkgs.stdenvNoCC.mkDerivation {
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
    })
  ];

  systemd.user.services.gnome-keyring-auto-unlock = {
    Unit.Description = "Auto-unlock GNOME keyring";

    Service = {
      Type = "oneshot";
      ExecStart = "${config.home.homeDirectory}/bin/zhj gnome-keyring::auto-unlock --verbose --no-callback";
    };
  };

  systemd.user.timers.gnome-keyring-auto-unlock = {
    Unit.Description = "Auto-unlock GNOME keyring every 5 minutes";
    Timer.OnCalendar = "*:0/5"; # every 5 min
    Install.WantedBy = [ "timers.target" ];
  };
}
