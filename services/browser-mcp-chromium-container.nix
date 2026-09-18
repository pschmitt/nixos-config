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
  meshHosts = config.custom.meshHosts "browser";
  primaryHost = builtins.head meshHosts;
  serverAliases = builtins.tail meshHosts;
  # haIngressBypass = false: that test needs a map from
  # services/authelia-nginx-bypass.nix, which only the host running Home
  # Assistant's ingress imports, and nginx refuses to start without it.
  autheliaConfig = import ./authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };
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

  # These names only resolve to mesh addresses, but nginx answers on 0.0.0.0,
  # so a request can reach this vhost anyway by sending its SNI to the WAN
  # address. Authelia therefore stays in front of the VNC session and decides
  # by source network: straight through from the mesh (see the mesh rule in
  # services/authelia.nix), a login prompt from anywhere else. The MCP clients
  # are unaffected -- they reach Chromium over ssh on 127.0.0.1:9222, not
  # through nginx.
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
