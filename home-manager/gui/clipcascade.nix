{ pkgs, lib, ... }:
let
  giTypelibs = lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.gdk-pixbuf
    pkgs.gobject-introspection
    pkgs.gtk3
    pkgs.libayatana-appindicator
  ];

  xdgDataDirs = lib.makeSearchPath "share" [
    pkgs.gsettings-desktop-schemas
    pkgs.gtk3
    pkgs.libayatana-appindicator
    pkgs.shared-mime-info
  ];
in
{
  systemd.user.services.clipcascade = {
    Unit = {
      Description = "ClipCascade clipboard sync";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
      Wants = [ "network-online.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.clipcascade}/bin/clipcascade";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "PYTHONUNBUFFERED=1"
        "GI_TYPELIB_PATH=${giTypelibs}"
        "XDG_DATA_DIRS=${xdgDataDirs}"
      ];
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
