{ lib, ... }:
{
  imports = [
    ./network.nix
    ../../misc/nix-distributed-build.nix
    ../../services/bitwarden.nix
  ];

  services.logind.lidSwitchExternalPower = lib.mkDefault "suspend";
}
