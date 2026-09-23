{ config, pkgs, ... }:
let
  apiKey = config.sops.secrets."immich/immich-mcp/apiKey".path;
in
{
  sops.secrets."immich/immich-mcp/apiKey" = {
    mode = "0600";
    sopsFile = config.host.sopsFile;
  };

  programs.mcp.servers.immich = {
    command = "${pkgs.immich-mcp}/bin/ImmichMCP";
    args = [ "--stdio" ];
    env = {
      IMMICH_API_KEY.file = apiKey;
      IMMICH_BASE_URL = "https://img.${config.domains.main}";
      IMMICH_TOOL_MODE = "static";
    };
  };
}
