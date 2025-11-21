{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  ge2Host = osConfig != null && osConfig.networking.hostName == "ge2";

  obsDesktopEntry = lib.attrByPath [ "xdg" "desktopEntries" "obs-studio-custom" ] null config;

  obsAutostartDesktop = lib.optionals (obsDesktopEntry != null) [
    "${config.home.profileDirectory}/share/applications/obs-studio-custom.desktop"
  ];
in
{
  xdg.autostart = {
    enable = true;
    readOnly = true;
    entries = [
      "${pkgs.nextcloud-client}/share/applications/com.nextcloud.desktopclient.nextcloud.desktop"
    ]
    ++ lib.optionals ge2Host obsAutostartDesktop;
  };
}
