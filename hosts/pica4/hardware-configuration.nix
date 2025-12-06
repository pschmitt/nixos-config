{ ... }:
{
  imports = [
    ../../hardware/rpi4.nix
    ./config-txt.nix
    ./power-monitoring.nix
  ];
}
