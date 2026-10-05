{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../../pkgs/termux-native/package-set.nix {
    inherit inputs pkgs;
  };
  jc = if termuxMode then termuxPackageSet.termuxPackages.jc else pkgs.jc;
  completions = pkgs.runCommand "jc-zsh-completions" { } ''
    mkdir -p "$out"
    ${pkgs.buildPackages.jc}/bin/jc -q --zsh-comp > "$out/_jc"
  '';
in
{
  home.packages = [ jc ];
  xdg.configFile."zsh/completions/_jc".source = "${completions}/_jc";

  programs.zsh.initContent = lib.mkIf termuxMode (
    lib.mkOrder 1500 ''
      if [[ -o interactive && -n "''${_comps+x}" ]]
      then
        autoload -Uz _jc
        compdef _jc jc
      fi
    ''
  );
}
