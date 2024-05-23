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
    };
  };

  environment.systemPackages = netbirdScripts;

  # mask netbird-wt0 service
  systemd.services.netbird-wt0.enable = false;

  sops.secrets."netbird/setup-keys/netbird-io" = { };

  systemd.services.netbird-netbird-io-autoconnect = {
    after = [ "netbird-netbird-io.service" ];
    wants = [ "netbird-netbird-io.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    path = netbirdScripts ++ [ pkgs.jq ];
    script = ''
      # NOTE When not connected/authorized, the status command will return:
      # Daemon status: NeedsLogin
      #
      # Run UP command to log in with SSO (interactive login):
      #
      #  netbird up
      #
      # If you are running a self-hosted version and no SSO provider has been configured in your Management Server,
      # you can use a setup-key:
      #
      #  netbird up --management-url <YOUR_MANAGEMENT_URL> --setup-key <YOUR_SETUP_KEY>
      #
      # More info: https://docs.netbird.io/how-to/register-machines-using-setup-keys
      if netbird-netbird-io status | grep -q 'NeedsLogin'
      then
        SETUP_KEY=$(cat ${config.sops.secrets."netbird/setup-keys/netbird-io".path})
        netbird-netbird-io up --setup-key "$SETUP_KEY"
      fi
    '';
  };
}
