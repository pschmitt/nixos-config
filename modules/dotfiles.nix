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
      alongside the yadm-managed shell
    '';
  };
}
