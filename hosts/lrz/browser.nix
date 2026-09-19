{ config, pkgs, ... }:
let
  meshHosts = config.custom.meshHosts "browser";
  primaryHost = builtins.head meshHosts;
  serverAliases = builtins.tail meshHosts;
  autheliaConfig = import ../../services/authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };
  waitForDisplay = pkgs.writeShellApplication {
    name = "lrz-browser-vnc";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.xdpyinfo
      pkgs.x11vnc
    ];
    text = builtins.readFile ./scripts/browser-vnc.sh;
  };
  commonService = {
    User = "lrz-browser";
    Group = "lrz-browser";
    UMask = "0077";
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "strict";
    Restart = "on-failure";
    RestartSec = "5s";
  };
in
{
  imports = [ ../../services/http.nix ];

  users = {
    groups.lrz-browser = { };
    users.lrz-browser = {
      isSystemUser = true;
      group = "lrz-browser";
      home = "/var/lib/lrz-browser";
    };
  };

  environment.systemPackages = [ pkgs.playwright-mcp ];

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/lrz-browser 0750 lrz-browser lrz-browser -"
      "d /var/lib/lrz-browser/mcp-downloads 0775 lrz-browser users -"
    ];

    targets.lrz-browser = {
      description = "Isolated lrz browser staging";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "lrz-browser.service"
        "lrz-browser-vnc.service"
        "lrz-browser-web.service"
      ];
      after = [
        "lrz-browser.service"
        "lrz-browser-vnc.service"
        "lrz-browser-web.service"
      ];
    };

    services = {
      lrz-browser = {
        description = "Native staging Chromium with private X11 display and CDP";
        partOf = [ "lrz-browser.target" ];
        environment = {
          HOME = "/var/lib/lrz-browser";
          XDG_RUNTIME_DIR = "/run/lrz-browser";
        };
        serviceConfig = commonService // {
          StateDirectory = "lrz-browser";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "lrz-browser";
          RuntimeDirectoryMode = "0700";
          # xvfb-run uses Xauthority; do not disable X access control or Chromium's sandbox.
          ExecStart = "${pkgs.xvfb-run}/bin/xvfb-run -n 97 -f /run/lrz-browser/Xauthority -s '-screen 0 1440x900x24 -nolisten tcp' ${pkgs.chromium}/bin/chromium --user-data-dir=/var/lib/lrz-browser/profile --no-first-run --no-default-browser-check --disable-sync --password-store=basic --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 --start-maximized --window-size=1440,900 about:blank";
        };
      };

      lrz-browser-vnc = {
        description = "Loopback VNC for the lrz staging display";
        requires = [ "lrz-browser.service" ];
        after = [ "lrz-browser.service" ];
        partOf = [ "lrz-browser.target" ];
        # Share the browser's private X11 socket namespace.
        unitConfig.JoinsNamespaceOf = "lrz-browser.service";
        environment = {
          DISPLAY = ":97";
          XAUTHORITY = "/run/lrz-browser/Xauthority";
        };
        serviceConfig = commonService // {
          ExecStart = "${waitForDisplay}/bin/lrz-browser-vnc";
        };
      };

      lrz-browser-web = {
        description = "Loopback noVNC WebSocket proxy for lrz staging";
        requires = [ "lrz-browser-vnc.service" ];
        after = [ "lrz-browser-vnc.service" ];
        partOf = [ "lrz-browser.target" ];
        serviceConfig = commonService // {
          ExecStart = "${pkgs.python3Packages.websockify}/bin/websockify --web ${pkgs.novnc}/share/webapps/novnc 127.0.0.1:6081 127.0.0.1:5907";
          NoNewPrivileges = true;
        };
      };
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
      proxyPass = "http://127.0.0.1:6081";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = autheliaConfig.location + ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
