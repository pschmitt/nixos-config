{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.services.ha-mcp;
  # renovate: datasource=docker depName=ghcr.io/homeassistant-ai/ha-mcp
  version = "9.3.0";
  # ha-mcp supplies a Uvicorn logging config that ignores FASTMCP_LOG_LEVEL.
  # Its access log otherwise records the secret MCP path on every request.
  serverEntrypoint = pkgs.writeText "ha-mcp-web.py" ''
    import uvicorn.config

    uvicorn.config.LOGGING_CONFIG["loggers"]["uvicorn.access"]["level"] = "WARNING"

    from ha_mcp.__main__ import main_web

    main_web()
  '';
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
      cmd = [
        "python"
        "/etc/ha-mcp-web.py"
      ];
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
      volumes = [
        "${serverEntrypoint}:/etc/ha-mcp-web.py:ro"
        "ha-mcp-${name}:/home/mcpuser/.ha-mcp"
      ];
    };
  }) cfg.instances;
}
