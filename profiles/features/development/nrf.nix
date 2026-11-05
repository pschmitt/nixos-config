{ pkgs, ... }:
{
  nixpkgs = {
    config = {
      allowUnfree = true;
      segger-jlink.acceptLicense = true;
      permittedInsecurePackages = [
        "segger-jlink-qt4-810"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    nrfutil
    nrfconnect
    nrfconnect-bluetooth-low-energy
  ];

  services.udev.packages = [ pkgs.nrf-udev ];
}
