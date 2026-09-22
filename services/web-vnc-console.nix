{
  config,
  pkgs,
  ...
}:
let
  port = 6080;
  meshHostsVnc = config.domains.meshHosts "vnc";
  meshHostsWebVnc = config.domains.meshHosts "web-vnc";
  allHosts = meshHostsVnc ++ meshHostsWebVnc;
  primaryHost = builtins.head allHosts;
  serverAliases = builtins.tail allHosts;
  autheliaConfig = import ./authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };
in
{
  imports = [ ./http.nix ];

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
      ExecStart = "${pkgs.python3Packages.websockify}/bin/websockify --web ${pkgs.novnc}/share/webapps/novnc 127.0.0.1:${toString port} 127.0.0.1:5900";
    };
  };

  services.nginx.virtualHosts."${primaryHost}" = {
    inherit serverAliases;
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    extraConfig = autheliaConfig.server;

    locations."= /" = {
      return = "302 /vnc.html?autoconnect=true&resize=remote";
    };

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = autheliaConfig.location + ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
