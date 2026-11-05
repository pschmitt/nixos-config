{ lib, pkgs, ... }:
{
  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };

  environment.systemPackages = with pkgs; [
    waydroid-helper
  ];

  # disable auto-start
  systemd.services.waydroid-container.wantedBy = lib.mkForce [ ];
}
