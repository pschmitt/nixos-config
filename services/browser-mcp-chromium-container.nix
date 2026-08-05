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

  # Real desktop Chromium (KasmVNC web UI on :48945/:48946) so the Browser MCP
  # Chrome extension has something to drive, and a human can VNC in when
  # manual intervention is needed. --network=host is required: the extension
  # always dials the MCP server at ws://localhost:9009, and that server runs
  # as a plain host process (spawned over ssh from fnuc's Claude Code config,
  # see hosts/fnuc/browser-mcp.nix) rather than inside this container.
  virtualisation.oci-containers.containers.${containerName} = {
    image = "lscr.io/linuxserver/chromium:latest";
    autoStart = true;
    hostname = containerName;
    environmentFiles = [ config.sops.templates."${containerName}.env".path ];
    volumes = [ "${dataDir}:/config" ];
    extraOptions = [
      "--network=host"
      "--shm-size=1g"
    ];
  };

  environment.systemPackages = [ pkgs.browsermcp ];
}
