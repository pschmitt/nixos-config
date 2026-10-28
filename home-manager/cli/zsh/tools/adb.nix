{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../pkgs/termux/native/package-set.nix {
    inherit inputs pkgs;
  };
  # adb.sh is legacy: the adb:: zsh functions talk to adb directly. Termux
  # still ships it until its bundle drops it.
  adbSh = termuxPackageSet.termuxPackages.adb-sh;
  adbCompletions = pkgs.callPackage ../../../../pkgs/zsh-tools/adb-completions.nix { };
in
{
  home.packages = if termuxMode then [ adbSh ] else [ pkgs.android-tools ];

  # The package ships it as _adb (#compdef adb.sh ads); prepending its
  # site-functions to fpath shadowed zsh's own _adb for the real adb.
  xdg.configFile."zsh/completions/_adb.sh" = lib.mkIf termuxMode {
    source = "${adbCompletions}/share/zsh/site-functions/_adb";
  };

  programs.zsh.initContent = lib.mkIf termuxMode (
    lib.mkOrder 1500 ''
      if [[ -o interactive && -n "''${_comps+x}" ]]
      then
        autoload -Uz _adb.sh
        compdef _adb.sh adb.sh ads
      fi
    ''
  );
}
