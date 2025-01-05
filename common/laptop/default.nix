{ inputs, lib, ... }:
{
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop

    ./network.nix
    ../../misc/nix-distributed-build.nix
    ../../services/bitwarden.nix
  ];

  services.logind.lidSwitchExternalPower = lib.mkDefault "suspend";
}
