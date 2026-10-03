{
  config,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxEget = pkgs.callPackage ../../pkgs/termux-native/go-binary.nix {
    inherit pkgs;
    package = pkgs.eget;
    binary = "eget";
  };
in
{
  home.packages = [ (if termuxMode then termuxEget else pkgs.eget) ];
}
