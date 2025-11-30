{ pkgs, ... }:
{
  systemd.services.vpn-test = {
    description = "VPN Test Service";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
    };
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
  };
}
