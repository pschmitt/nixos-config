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
  tmuxXpanes = termuxPackageSet.termuxPackages.tmux-xpanes;
in
{
  home.packages = lib.optionals termuxMode [ tmuxXpanes ];
  xdg.configFile = lib.mkIf termuxMode {
    "tmux/bin/xpanes".source = "${tmuxXpanes}/bin/xpanes";
    "zsh/completions/_xpanes".source = "${tmuxXpanes}/share/zsh/site-functions/_xpanes";
  };
  xdg.dataFile."man/man1/xpanes.1" = lib.mkIf termuxMode {
    source = "${tmuxXpanes}/share/man/man1/xpanes.1";
  };

  programs.zsh.initContent = lib.mkIf termuxMode (
    lib.mkOrder 1500 ''
      if [[ -o interactive && -n "''${_comps+x}" ]]
      then
        autoload -Uz _xpanes
        compdef _xpanes xpanes
      fi
    ''
  );
}
