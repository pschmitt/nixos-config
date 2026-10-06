{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../pkgs/termux-native/package-set.nix {
    inherit inputs pkgs;
  };
  adbSh = termuxPackageSet.termuxPackages.adb-sh;
  adbCompletions =
    if termuxMode then
      pkgs.callPackage ../../../../pkgs/zsh-tools/adb-completions.nix { }
    else
      pkgs.adb-completions;
in
{
  home.packages =
    if termuxMode then
      [ adbSh ]
    else
      [
        pkgs.adb-sh
        pkgs.android-tools
        pkgs.adb-completions
      ];

  xdg.configFile."zsh/completions/_adb.sh" = lib.mkIf termuxMode {
    source = "${adbCompletions}/share/zsh/site-functions/_adb";
  };

  programs.zsh.initContent =
    if termuxMode then
      lib.mkOrder 1500 ''
        if [[ -o interactive && -n "''${_comps+x}" ]]
        then
          autoload -Uz _adb.sh
          compdef _adb.sh adb.sh ads
        fi
      ''
    else
      ''
        fpath=("${adbCompletions}/share/zsh/site-functions" $fpath)
      '';
}
