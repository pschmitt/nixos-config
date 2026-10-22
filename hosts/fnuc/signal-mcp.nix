{
  config,
  lib,
  pkgs,
  ...
}:
let
  signalMcp = pkgs.writers.writePython3Bin "signal-mcp" {
    libraries = [ pkgs.python3Packages.mcp ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/signal-mcp.py);
in
{
  # The user's own number stays out of the store: the MCP reads it from the
  # secret on each send.
  sops.secrets."signal/me" = config.sops.mkHostSecret {
    owner = config.mainUser.username;
  };

  # signal-cli daemon of the Hermes gateway (services/hermes.nix), reachable
  # over the mesh only.
  home-manager.users.${config.mainUser.username}.programs.mcp.servers.signal = {
    command = lib.getExe signalMcp;
    args = [
      "--url"
      "http://rofl-10:8712"
      "--recipient"
      "me=${config.sops.secrets."signal/me".path}"
    ];
  };
}
