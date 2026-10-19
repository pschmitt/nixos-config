{
  config,
  inputs,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  inherit (import ../../../../pkgs/termux/native/package-set.nix { inherit inputs pkgs; })
    termuxPackages
    ;
in
{
  home.packages = [
    (
      if termuxMode then
        termuxPackages.nbx
      else
        inputs.nbx.packages.${pkgs.stdenv.hostPlatform.system}.default
    )
  ];
}
