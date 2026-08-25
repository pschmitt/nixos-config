{ config, pkgs, ... }:
let
  containerName = "browser-mcp-chromium";
  dataDir = "/var/lib/${containerName}";
in
{
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
    CUSTOM_PORT=48945
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

  environment.systemPackages = [ pkgs.playwright-mcp ];
}
