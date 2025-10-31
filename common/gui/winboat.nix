{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    # NOTE w/o adding freerdp here, winboat fails to detect it at runtime
    pkgs.freerdp
    inputs.winboat.packages.${pkgs.system}.winboat
  ];
}
