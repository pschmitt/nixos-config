{ config, pkgs, ... }:
let
  containerName = "browser-mcp-chromium";
  dataDir = "/var/lib/${containerName}";
  # Bind-mounted at this exact same absolute path in the container (in
  # addition to already being visible under dataDir's /config mount) so that
  # playwright-mcp (running bare on the host, see home-manager/devel/ai.nix)
  # and Chromium
  # (running in the container) agree on one literal path for --output-dir:
  # Chrome is told over CDP to save downloads there, and that path has to
  # resolve to a real, writable directory in both mount namespaces.
  downloadsDir = "${dataDir}/mcp-downloads";
  containerPort = 48945;
  # Pin PUID/PGID explicitly and reuse the same values for the mount root's
  # ownership so the container can always write to it (e.g. to create
  # ~/Downloads), instead of relying on the linuxserver image's uid/gid 911
  # default.
  puid = 1000;
  pgid = 1000;
  # browser.<host>.<mesh domain>, via the shared helper so this and the Glance
  # dashboard expose mesh names the same way.
  meshHosts = config.domains.meshHosts "browser";
  primaryHost = builtins.head meshHosts;
  serverAliases = builtins.tail meshHosts;
  # haIngressBypass = false: that test needs a map from
  # services/authelia-nginx-bypass.nix, which only the host running Home
  # Assistant's ingress imports, and nginx refuses to start without it.
  autheliaConfig = import ./authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };
  # Docker/host restarts never give Chromium a clean shutdown (exit_type
  # stays "Crashed"), and Chromium's cookie store purges session-only
  # cookies (no expiry, e.g. most SSO logins) at the *next* startup whenever
  # session.restore_on_startup != 1. Force "continue where you left off" via
  # enterprise policy -- rather than the mutable Preferences file, which
  # this doesn't touch -- so logins survive container/host restarts instead
  # of only surviving alongside the on-disk profile.
  restoreSessionPolicy = pkgs.writeText "browser-mcp-chromium-restore-session.json" (
    builtins.toJSON { RestoreOnStartup = 1; }
  );
in
{
  imports = [ ./http.nix ];

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${toString puid} ${toString pgid} - -"
    "d ${downloadsDir} 0750 ${toString puid} ${toString pgid} - -"
  ];

  # Keep a persistent GUI browser for human logins and CAPTCHAs. Playwright MCP
  # connects over CDP from the same host, so it sees the logged-in profile and
  # needs no browser extension or manual enablement.
  virtualisation.oci-containers.containers.${containerName} = {
    image = "lscr.io/linuxserver/chromium:latest";
    autoStart = true;
    hostname = containerName;
    environment = {
      PUID = toString puid;
      PGID = toString pgid;
      CUSTOM_PORT = toString containerPort;
      CUSTOM_HTTPS_PORT = "48946";
      CHROME_CLI = "--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222";
    };
    volumes = [
      "${dataDir}:/config"
      "${downloadsDir}:${downloadsDir}"
      "${restoreSessionPolicy}:/etc/chromium/policies/managed/restore-session.json:ro"
    ];
    extraOptions = [
      "--network=host"
      "--shm-size=1g"
    ];
  };

  # Authelia gates access to this vhost via SSO (see the browser rule in
  # services/authelia.nix), protecting the session on both mesh and WAN
  # without needing container-level Basic Auth. The MCP clients are unaffected
  # -- they reach Chromium over ssh on 127.0.0.1:9222, not through nginx.
  services.nginx.virtualHosts."${primaryHost}" = {
    inherit serverAliases;
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;
    extraConfig = autheliaConfig.server;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString containerPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = autheliaConfig.location + ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  environment.systemPackages = [ pkgs.playwright-mcp ];
}
