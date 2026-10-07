{
  inputs,
  pkgs,
  ...
}:
let
  termuxTools = pkgs.callPackage ../../../../../pkgs/termux/native/termux-tools.nix {
    package = inputs.termux-tools;
  };
in
{
  home.packages = [ termuxTools ];
}
