{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxZoxide = pkgs.callPackage ../../../pkgs/termux-native/zoxide.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.zoxide.override { withFzf = false; };
  };
  zoxideInitFile = pkgs.runCommand "zoxide-init" { } ''
    mkdir -p $out
    ${pkgs.zoxide}/bin/zoxide init zsh --no-cmd > $out/init.zsh
  '';
in
{
  home.packages = [ (if termuxMode then termuxZoxide else pkgs.zoxide) ];

  xdg.configFile."zsh/custom/os/home-manager/system.zsh" = lib.mkIf (!termuxMode) {
    text = lib.mkAfter ''
      # zoxide
      source ${zoxideInitFile}/init.zsh
      alias z=__zoxide_z
      alias zz=__zoxide_zi
    '';
  };
}
