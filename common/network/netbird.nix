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

  # mask netbird-wt0 service
  systemd.services.netbird-wt0.enable = false;
}
