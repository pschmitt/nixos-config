{ config, lib, ... }:
{
  # FIXME Disable wait-online services, this somehow results in NM not being started at all.
  # systemd.network.wait-online.enable = false;
  # systemd.services.NetworkManager-wait-online.enable = false;

  # Enable NetworkManager
  networking = {
    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
    };
  };

  custom.netbirdSetupKey = lib.mkForce "laptop";

  users.users."${config.custom.username}".extraGroups = [ "networkmanager" ];

  services.tailscale.extraUpFlags = [
    "--accept-routes"
    "--advertise-exit-node"
    "--operator=${config.custom.username}"
  ];
}
