{
  config,
  pkgs,
  lib,
  ...
}:
let
  createNetbirdScript =
    tunnelName: tunnelConfig:
    pkgs.writeShellScriptBin "netbird-${tunnelName}" ''
      # Set environment variables
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: ''export ${name}="${value}"'') tunnelConfig.environment
      )}

      # Run netbird
      # TODO Stupidly prepending sudo to the command doesn't work and just
      # breaks the netbird cli
      # exec /run/wrappers/bin/sudo ${pkgs.netbird}/bin/netbird "$@"
      exec ${pkgs.netbird}/bin/netbird "$@"
    '';

  netbirdScripts = lib.mapAttrsToList createNetbirdScript config.services.netbird.tunnels;
in
{
  services.netbird = {
    enable = true;
    tunnels = {
      wiit = {
        port = 51821;
        environment = {
          NB_MANAGEMENT_URL = "https://nb.gec.io";
          NB_ALLOW_SSH = "false";
        };
      };
    };
  };

  environment.systemPackages = netbirdScripts;
}
