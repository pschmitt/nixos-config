{ pkgs, ... }:
{
  imports = [
    ./am-i-mullvad.nix
  ];

  services.mullvad-vpn = {
    enable = true;
    gui.enable = true;
    enableExcludeWrapper = true;
  };

  environment.systemPackages = with pkgs; [
    master.mullvad-compass
    mullvad-browser
  ];
}
