{ lib, ... }:

{
  options.dotfiles = {
    promptColor = lib.mkOption {
      type = lib.types.str;
      default = "white";
      description = "Main user's prompt color";
    };

    zsh.nixShell.enable = lib.mkEnableOption ''
      the Nix-managed Zsh shell (`zsh-nix` launcher and ~/.config/zsh-nix)
      alongside the yadm-managed shell (on by default on Home Manager hosts)
    '';

    zsh.nixShell.default = lib.mkEnableOption ''
      the Nix-managed Zsh config as the default ZDOTDIR (~/.config/zsh-nix);
      the yadm-managed shell stays reachable via `zsh-yadm` (on by default on
      Home Manager hosts)
    '';
  };
}
