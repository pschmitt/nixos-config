{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath;
  viQuote = pkgs.fetchFromGitHub {
    owner = "zsh-vi-more";
    repo = "vi-quote";
    rev = "13399086a4c31e8c0e09562ca0c4205ee4c055bd";
    hash = "sha256-c8Z+HNxeoSehBAbwCCCVyYVOUOzcc51nE5A1pvtIkV0=";
  };
in
{
  programs.zsh.initContent = lib.mkOrder 948 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::source-plugin ${pluginPath "vi-quote" "vi-quote.plugin.zsh" "${viQuote}/vi-quote.plugin.zsh"}
    fi
  '';
}
