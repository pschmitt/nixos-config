{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.services.ha-mcp;
  # renovate: datasource=docker depName=ghcr.io/homeassistant-ai/ha-mcp
  version = "9.2.0";
  instance = {
    options = {
      homeAssistantUrl = mkOption {
        type = types.str;
        description = "Home Assistant URL used by this server.";
      };
      tokenEnvironmentFile = mkOption {
        type = types.str;
        description = "Runtime environment file containing HOMEASSISTANT_TOKEN.";
      };
      serverEnvironmentFile = mkOption {
        type = types.str;
        description = "Runtime environment file containing MCP_SECRET_PATH.";
      };
      port = mkOption {
        type = types.port;
        description = "Loopback port for this server's MCP endpoint.";
      };
    };
  };
in
{
  options.services.ha-mcp.instances = mkOption {
    type = types.attrsOf (types.submodule instance);
    default = { };
    description = "Independent ha-mcp servers with their own Home Assistant credentials.";
  };

  config.virtualisation.oci-containers.containers = lib.mapAttrs' (name: instance: {
    name = "ha-mcp-${name}";
    value = {
      image = "ghcr.io/homeassistant-ai/ha-mcp:${version}";
      cmd = [ "ha-mcp-web" ];
      environment = {
        HOMEASSISTANT_URL = instance.homeAssistantUrl;
        HA_MCP_DISABLE_SETTINGS_UI = "true";
        LOG_LEVEL = "WARNING";
      };
      environmentFiles = [
        instance.tokenEnvironmentFile
        instance.serverEnvironmentFile
      ];
      ports = [ "127.0.0.1:${toString instance.port}:8086" ];
      volumes = [ "ha-mcp-${name}:/home/mcpuser/.ha-mcp" ];
    };
  }) cfg.instances;
}
