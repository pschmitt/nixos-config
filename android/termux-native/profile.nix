{ pkgs, inputs }:
{
  # Copy unmodified sources, not Nixpkgs outputs with host shebangs/store paths.
  plugins = {
    diff-so-fancy = "${pkgs.zsh-diff-so-fancy}/share/zsh/plugins/zsh-diff-so-fancy";
    autosuggestions = pkgs.zsh-autosuggestions.src;
    syntax-highlighting = pkgs.zsh-syntax-highlighting.src;
    history-substring-search = pkgs.zsh-history-substring-search.src;
    autopair = pkgs.zsh-autopair.src;
    completions = inputs.zsh-completions;
    powerlevel10k = pkgs.zsh-powerlevel10k.src;
    oh-my-zsh = pkgs.oh-my-zsh.src;
    prezto-archive = "${pkgs.zsh-prezto.src}/modules/archive";
    emoji-fzf = pkgs.fetchFromGitHub {
      owner = "pschmitt";
      repo = "emoji-fzf.zsh";
      rev = "55c7cb68b16f460f01b92651c11a7190e803f236";
      hash = "sha256-/yNpAEQlR+5n8cJqcG5+VciVdguxSd7At2XadUbva6g=";
    };
    inherit (inputs) manydots vi-motions vi-quote;
  };
}
