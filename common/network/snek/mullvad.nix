{ pkgs, ... }:
{
  imports = [
    ./am-i-mullvad.nix
  ];

  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn; # cli + gui
    enableExcludeWrapper = true;
  };

  environment.systemPackages = with pkgs; [
    mullvad-compass
    mullvad-browser
  ];
}
