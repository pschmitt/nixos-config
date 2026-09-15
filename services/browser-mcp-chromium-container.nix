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
  primaryHost = "browser.${config.networking.hostName}.${config.domains.tailscale}";
  serverAliases = [
    "browser.${config.networking.hostName}.${config.domains.netbird}"
    "browser.${config.networking.hostName}.${config.domains.vpn}"
  ];
in
{
  imports = [ ./http.nix ];

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${toString puid} ${toString pgid} - -"
    "d ${downloadsDir} 0750 ${toString puid} ${toString pgid} - -"
  ];

  sops.secrets = {
    "browser-mcp/vnc/user" = config.custom.mkSecret { };
    "browser-mcp/vnc/password" = config.custom.mkSecret { };
  };

  sops.templates."${containerName}.env".content = ''
    CUSTOM_USER=${config.sops.placeholder."browser-mcp/vnc/user"}
    PASSWORD=${config.sops.placeholder."browser-mcp/vnc/password"}
    CUSTOM_PORT=${toString containerPort}
    CUSTOM_HTTPS_PORT=48946
  '';

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
      CHROME_CLI = "--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222";
    };
    environmentFiles = [ config.sops.templates."${containerName}.env".path ];
    volumes = [
      "${dataDir}:/config"
      "${downloadsDir}:${downloadsDir}"
    ];
    extraOptions = [
      "--network=host"
      "--shm-size=1g"
    ];
  };

  services.nginx.virtualHosts."${primaryHost}" = {
    inherit serverAliases;
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString containerPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  environment.systemPackages = [ pkgs.playwright-mcp ];
}
