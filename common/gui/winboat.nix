{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    # NOTE w/o adding freerdp3 here, winboat fails to detect it at runtime
    pkgs.freerdp3
    inputs.winboat.packages.${pkgs.system}.winboat
  ];
}
