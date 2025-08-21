{ inputs, ... }:
{
  imports = [
    inputs.hardware.nixosModules.raspberry-pi-4
  ];
}
