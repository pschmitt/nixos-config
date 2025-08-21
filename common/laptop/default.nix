{ inputs, lib, ... }:
{
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop

    ./network.nix
    ./wireshark.nix
    ../../services/bitwarden.nix
    ../../services/nix-distributed-build.nix
  ];

  services.logind.lidSwitchExternalPower = lib.mkDefault "suspend";
}
