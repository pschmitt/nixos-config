{
  config,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxRipgrep = pkgs.callPackage ../../pkgs/termux-native/from-nixpkgs.nix {
    package = pkgs.ripgrep;
    skipPostFixup = true;
    crossPackage = pkgs.pkgsCross.aarch64-android-prebuilt.ripgrep.override { withPCRE2 = false; };
  };
in
{
  home.packages = [ (if termuxMode then termuxRipgrep else pkgs.ripgrep) ];
}
