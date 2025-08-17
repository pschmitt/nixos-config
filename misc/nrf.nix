{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.segger-jlink.acceptLicense = true;

  nixpkgs.config.permittedInsecurePackages = [
    "segger-jlink-qt4-810"
  ];

  environment.systemPackages = with pkgs; [
    nrfutil
    nrf-udev
    nrfconnect
    nrfconnect-bluetooth-low-energy
  ];
}
