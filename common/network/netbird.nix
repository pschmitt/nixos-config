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
  sops = {
    secrets.netbird-setup-key = {
      key = "netbird/setup-keys/netbird-io/${config.custom.netbirdSetupKey}";
    };
    templates.netbird-auth.content = ''
      NB_SETUP_KEY=${config.sops.placeholder.netbird-setup-key}
    '';
  };

  services.netbird = {
    enable = true;
    tunnels = {
      netbird-io = {
        port = 51820;
        environment = {
          NB_MANAGEMENT_URL = "https://api.netbird.io";
          # Below won't work
          # You will end up with NB_SETUP_KEY=<SOPS:xxxx:PLACEHOLDER>
          # NB_SETUP_KEY = "${config.sops.placeholder.netbird-setup-key}";
        };
      };
    };
  };

  # mask netbird-wt0 service
  systemd.services.netbird-wt0.enable = false;

  systemd.services.netbird-netbird-io = {
    postStart = ''
      export PATH=${
        pkgs.lib.makeBinPath (
          netbirdScripts
          ++ [
            pkgs.coreutils
            pkgs.gnugrep
          ]
        )
      }
      # sleep 5
      if netbird-netbird-io status | \
        grep -q 'NeedsLogin'
      then
        netbird-netbird-io up --setup-key-file "${config.sops.secrets.netbird-setup-key.path}"
      fi
    '';

    # FIXME Below does not seem to be working... The NB_SETUP_KEY is correctly
    # set but netbird seems to just ignore it.
    serviceConfig.EnvironmentFile = config.sops.templates."netbird-auth".path;
  };

  environment.systemPackages = netbirdScripts;
}
