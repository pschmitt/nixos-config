{
  config,
  inputs,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  inherit
    (import ../../../../pkgs/termux-native/package-set.nix {
      inherit inputs pkgs;
    })
    termuxPackages
    ;
in
{
  home.packages = [
    (if termuxMode then termuxPackages.kubectlSocks5Proxy else pkgs.kubectl-socks5-proxy)
  ];
}
