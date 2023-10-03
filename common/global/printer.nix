{ inputs, outputs, lib, config, pkgs, ... }:

{
  services.printing.enable = true;
  services.printing.drivers = with pkgs; [ cups-brother-hll2340dw ];
}
