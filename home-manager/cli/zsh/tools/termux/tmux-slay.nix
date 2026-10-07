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
  tmuxSlay = termuxPackageSet.termuxPackages.tmux-slay;
in
{
  home.packages = lib.optionals termuxMode [ tmuxSlay ];
  xdg.configFile."zsh/completions/_tmux-slay" = lib.mkIf termuxMode {
    source = "${tmuxSlay}/share/zsh/site-functions/_tmux-slay";
  };

  programs.zsh.shellAliases.tslay = lib.mkIf termuxMode (lib.mkDefault "tmux-slay");
  programs.zsh.initContent = lib.mkIf termuxMode (
    lib.mkOrder 1500 ''
      if [[ -o interactive && -n "''${_comps+x}" ]]
      then
        autoload -Uz _tmux-slay
        compdef _tmux-slay tmux-slay
      fi
    ''
  );
}
