{ inputs, lib, ... }:
{
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop

    ../../services/bitwarden.nix
    ../../services/nix-distributed-build.nix

    ../wifi.nix
    ./network.nix
    ./wireshark.nix
  ];

  services.logind.settings.Login.HandleLidSwitchExternalPower = lib.mkDefault "suspend";
}
