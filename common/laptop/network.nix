{ config, lib, ... }:
{
  imports = [ ./tor.nix ];
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

  users.users."${config.mainUser.username}".extraGroups = [ "networkmanager" ];

  custom.netbirdSetupKey = lib.mkForce "laptop";

  services.tailscale.extraSetFlags = [
    "--accept-routes"
  ];
}
