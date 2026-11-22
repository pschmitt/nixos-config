{ pkgs, ... }:
{
  imports = [
    ./eget.nix
    ./zsh/tools/jq.nix
    ./zsh/tools/tables.nix
    ./zsh/tools/tmux-slay.nix
    ./zsh/tools/tmux-xpanes.nix
    ./zsh/tools/yank.nix
  ];

  home.packages = with pkgs; [
    emoji-fzf
    fzf-preview
    jsonrepair
    linkding-cli
    nix-your-shell
  ];
}
