{ pkgs, ... }:
{
  xdg.autostart = {
    enable = true;
    readOnly = true;
    entries = [
      "${pkgs.nextcloud-client}/share/applications/com.nextcloud.desktopclient.nextcloud.desktop"
    ];
  };
}
