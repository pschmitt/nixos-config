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
    };
  };

  users.users."${config.custom.username}".extraGroups = [ "netbird-netbird-io" ];

  services.netbird = {
    enable = true;
    package = netbirdPkg;
    clients = {
      netbird-io = {
        port = 51820;
      };
    };
  };

  # mask netbird-wt0 service
  systemd.services.netbird-wt0.enable = false;
}
