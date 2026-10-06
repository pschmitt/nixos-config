{ pkgs, inputs }:
let
  zshDiffSoFancy = pkgs.callPackage ../../pkgs/zsh-tools/zsh-diff-so-fancy.nix { inherit inputs; };
in
{
  # Copy unmodified sources, not Nixpkgs outputs with host shebangs/store paths.
  plugins = {
    inherit (inputs) alias-tips;
    diff-so-fancy = "${zshDiffSoFancy}/share/zsh/plugins/zsh-diff-so-fancy";
    autosuggestions = pkgs.zsh-autosuggestions.src;
    syntax-highlighting = pkgs.zsh-syntax-highlighting.src;
    history-substring-search = pkgs.zsh-history-substring-search.src;
    autopair = pkgs.zsh-autopair.src;
    completions = pkgs.zsh-completions.src;
    powerlevel10k = pkgs.zsh-powerlevel10k.src;
    zsh-defer = pkgs.zsh-defer.src;
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
