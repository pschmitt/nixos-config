{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxVivid = pkgs.callPackage ../../../pkgs/termux-native/vivid.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.vivid;
  };
in
{
  home.packages = [ (if termuxMode then termuxVivid else pkgs.vivid) ];

  programs.vivid = {
    enable = true;
    activeTheme = "one-dark";
    package = lib.mkIf termuxMode null;
  };

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    if termuxMode then
      ''
        # vivid
        export LS_COLORS="$(vivid generate ${config.programs.vivid.activeTheme})"
      ''
    else
      ''
        # vivid
        export LS_COLORS="$(cat ${
          (pkgs.runCommand "vivid-generate" { } ''
            mkdir -p $out
            ${pkgs.vivid}/bin/vivid generate ${config.programs.vivid.activeTheme} > $out/ls_colors
          '')
        }/ls_colors)"
      ''
  );
}
