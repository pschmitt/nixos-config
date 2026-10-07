{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../../pkgs/termux/native/package-set.nix {
    inherit inputs pkgs;
  };
  inherit (termuxPackageSet.termuxPackages) linkding-cli;
in
{
  home.packages = [ (if termuxMode then linkding-cli else pkgs.linkding-cli) ];
  xdg.configFile."zsh/completions/_linkding" = lib.mkIf termuxMode {
    source = "${linkding-cli}/share/zsh/site-functions/_linkding";
  };

  programs.zsh.initContent = lib.mkIf termuxMode (
    lib.mkOrder 1500 ''
      if [[ -o interactive && -n "''${_comps+x}" ]]
      then
        autoload -Uz _linkding
        compdef _linkding linkding
      fi
    ''
  );
}
