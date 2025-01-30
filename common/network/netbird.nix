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
    templates.netbird-auth.content = ''
      NB_SETUP_KEY=${config.sops.placeholder.netbird-setup-key}
    '';
  };

  users.users."${config.custom.username}".extraGroups = [ "netbird-netbird-io" ];

  services.netbird = {
    enable = true;
    package = netbirdPkg;
    clients = {
      netbird-io = {
        port = 51820;
        # environment = {
        #   NB_MANAGEMENT_URL = "https://api.netbird.io";
        #   # Below won't work
        #   # You will end up with NB_SETUP_KEY=<SOPS:xxxx:PLACEHOLDER>
        #   # NB_SETUP_KEY = "${config.sops.placeholder.netbird-setup-key}";
        # };
      };
    };
  };

  # mask netbird-wt0 service
  # systemd.services.netbird-wt0.enable = false;
}
