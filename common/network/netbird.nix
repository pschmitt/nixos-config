{
  config,
  pkgs,
  ...
}:
let
  netbirdPkg = pkgs.master.netbird;
in
{
  sops = {
    secrets.netbird-setup-key = {
      key = "netbird/setup-keys/netbird-io/${config.custom.netbirdSetupKey}";
      owner = "netbird-netbird-io";
      group = "netbird-netbird-io";
      mode = "0440";
    };
  };

  users.users."${config.custom.username}".extraGroups = [ "netbird-netbird-io" ];

  services.netbird = {
    enable = true;
    package = netbirdPkg;
    clients = {
      netbird-io = {
        port = 51820;
        dns-resolver = {
          address = "127.0.0.20";
          port = 53;
        };
      };
    };
  };

  systemd.services.netbird-netbird-io.postStart = ''
    NB_BIN=/run/current-system/sw/bin/netbird-netbird-io

    # HOTFIX Do an explicit netbird up. This is mostly for new hosts - as
    # they don't seem to come up on their own after provisioning.
    $NB_BIN up

    # Store Netbird IP address in /etc/netbird/netbird.env
    if NETBIRD_IP=$($NB_BIN status --ipv4) && [[ -n $NETBIRD_IP ]]
    then
      mkdir -p /etc/containers/env
      echo "NETBIRD_IP=$NETBIRD_IP" > /etc/containers/env/netbird.env
    fi
  '';

  # mask netbird-wt0 service
  systemd.services.netbird-wt0.enable = false;

  environment.shellInit = ''
    # netbird ip
    source /etc/containers/env/netbird.env 2>/dev/null
  '';
}
