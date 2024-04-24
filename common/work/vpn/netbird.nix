{ config, pkgs, lib, ... }:
let
  createNetbirdScript = tunnelName: tunnelConfig:
    pkgs.writeShellScriptBin "netbird-${tunnelName}" ''
      # Set environment variables
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "export ${name}=\"${value}\"") tunnelConfig.environment)}

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
      netbird-io = {
        port = 51820;
        environment = {
          NB_MANAGEMENT_URL = "https://api.netbird.io";
        };
      };
      wiit = {
        port = 51821;
        environment = {
          NB_MANAGEMENT_URL = "https://netbird-api.ooe.gecgo.net";
          # TODO Does this work?
          # https://docs.netbird.io/how-to/cli#environment-variables
          NB_ALLOW_SSH = "false";
        };
      };
    };
  };

  environment.systemPackages = netbirdScripts;

  # mask netbird-wt0 service
  systemd.services.netbird-wt0.enable = false;

  # Starting netbird before tailscaled ensures that (tailscale) hosts
  # resolution works as expected.
  # systemd.services.netbird-wt0.after = [ "tailscaled.service" ];
  # systemd.services.tailscaled.before = [ "netbird-wt0.service" ];
}
