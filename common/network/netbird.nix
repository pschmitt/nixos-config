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

  # HOTFIX Do an explicit netbird up. This is mostly for new hosts - as
  # they don't seem to come up on their own after provisioning.
  systemd.services.netbird-netbird-io.postStart = ''
    /run/current-system/sw/bin/netbird-netbird-io up
  '';

  # mask netbird-wt0 service
  systemd.services.netbird-wt0.enable = false;

  environment.shellInit = ''
    # netbird
    export NETBIRD_IP=$(${pkgs.iproute2}/bin/ip -j -4 addr show dev nb-netbird-io 2>/dev/null | \
      ${pkgs.jq}/bin/jq -er '.[0].addr_info[0].local' 2>/dev/null)
  '';
}
