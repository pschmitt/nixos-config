{
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  hostName = if osConfig == null then null else (osConfig.networking.hostName or null);
  ge2Host = hostName == "ge2";

  obsAutostartExec = "${
    pkgs.writeShellApplication {
      name = "obs-hyprland-autostart";
      runtimeInputs = with pkgs; [
        coreutils
        findutils
        flatpak
        gawk
        gnugrep
        obs-studio
        procps
      ];
      text = builtins.readFile ./obs-autostart.sh;
    }
  }/bin/obs-hyprland-autostart";

  obsAutostartDesktop = pkgs.writeText "obs-hyprland.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=OBS Studio (Custom)
    Comment=Start OBS with our custom flags
    Exec=${obsAutostartExec}
    TryExec=${obsAutostartExec}
    Terminal=false
    OnlyShowIn=Hyprland;
    X-GNOME-Autostart-enabled=true
  '';
in
{
  xdg.autostart = {
    enable = true;
    readOnly = true;
    entries = [
      "${pkgs.nextcloud-client}/share/applications/com.nextcloud.desktopclient.nextcloud.desktop"
    ]
    ++ lib.optionals ge2Host [ obsAutostartDesktop ];
  };
}
