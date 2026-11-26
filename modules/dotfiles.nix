{ lib, ... }:

{
  options.dotfiles = {
    promptColor = lib.mkOption {
      type = lib.types.str;
      default = "white";
      description = "Main user's prompt color";
    };

    promptHostAlias = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "fnc";
      description = "Short host name shown in the prompt and tmux status line instead of the hostname";
    };

    zsh.nixShell.enable = lib.mkEnableOption ''
      the Nix-managed Zsh config (startup files in ~/.config/zsh, on by
      default on Home Manager hosts)
    '';

    zsh.nixShell.default = lib.mkEnableOption ''
      the Nix-managed Zsh config as the user's default shell config, including
      the `zhj` helper (on by default on Home Manager hosts)
    '';
  };
}
