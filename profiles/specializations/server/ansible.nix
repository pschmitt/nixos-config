{ pkgs, inputs, ... }:
{
  environment.systemPackages = with pkgs; [
    python3
    inputs.nixos-needsreboot.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
