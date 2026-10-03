{ pkgs, inputs }:
{
  # Copy unmodified sources, not Nixpkgs outputs with host shebangs/store paths.
  plugins = {
    autosuggestions = pkgs.zsh-autosuggestions.src;
    syntax-highlighting = pkgs.zsh-syntax-highlighting.src;
    history-substring-search = pkgs.zsh-history-substring-search.src;
    autopair = pkgs.zsh-autopair.src;
    completions = pkgs.zsh-completions.src;
    powerlevel10k = pkgs.zsh-powerlevel10k.src;
    oh-my-zsh = pkgs.oh-my-zsh.src;
    inherit (inputs) manydots vi-motions vi-quote;
  };
}
