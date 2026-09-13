{ config, pkgs, ... }:
let
  containerName = "browser-mcp-chromium";
  dataDir = "/var/lib/${containerName}";
  containerPort = 48945;
  primaryHost = "browser.${config.networking.hostName}.${config.domains.tailscale}";
  serverAliases = [
    "browser.${config.networking.hostName}.${config.domains.netbird}"
    "browser.${config.networking.hostName}.${config.domains.vpn}"
  ];
in
{
  imports = [ ./http.nix ];

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root - -"
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
      CHROME_CLI = "--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222";
    };
    environmentFiles = [ config.sops.templates."${containerName}.env".path ];
    volumes = [ "${dataDir}:/config" ];
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
