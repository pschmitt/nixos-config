{ pkgs, ... }:
let
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
  # FNUC-014: opt-in staging, no production profile, DNS, credentials or clients.
  # Start lrz-browser.target manually after deployment. Tunnel 6081 (noVNC)
  # and/or 9223 (CDP) over SSH; every network listener is loopback-only.
  users.groups.lrz-browser = { };
  users.users.lrz-browser = {
    isSystemUser = true;
    group = "lrz-browser";
    home = "/var/lib/lrz-browser";
  };

  systemd.targets.lrz-browser = {
    description = "Isolated lrz browser staging (manual start only)";
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

  systemd.services = {
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
        ExecStart = "${pkgs.xvfb-run}/bin/xvfb-run -n 97 -f /run/lrz-browser/Xauthority -s '-screen 0 1440x900x24 -nolisten tcp' ${pkgs.chromium}/bin/chromium --user-data-dir=/var/lib/lrz-browser/profile --no-first-run --no-default-browser-check --disable-sync --password-store=basic --remote-debugging-address=127.0.0.1 --remote-debugging-port=9223 about:blank";
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
}
