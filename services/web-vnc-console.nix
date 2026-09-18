{
  pkgs,
  ...
}:
let
  port = 6080;
in
{
  systemd.services.novnc = {
    description = "noVNC Web Console for Home Assistant VM";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "libvirtd.service"
    ];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      Restart = "always";
      RestartSec = "5s";
      ExecStart = "${pkgs.python3Packages.websockify}/bin/websockify --web ${pkgs.novnc}/share/webapps/novnc ${toString port} 127.0.0.1:5900";
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
