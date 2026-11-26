{
  lib,
  pkgs,
  ...
}:
let
  viMotions = pkgs.fetchFromGitHub {
    owner = "zsh-vi-more";
    repo = "vi-motions";
    rev = "c21a9e13be15166810e9487a015cd70c21229cf7";
    hash = "sha256-sx6thchIjx2gTU5dKG+x0RKB2O/92RLOkHwKQ1P6xy8=";
  };
in
{
  # After bindkeys.nix (1300), so its Home/End bindings
  # (vi-beginning/end-of-line) win.
  programs.zsh.initContent = lib.mkOrder 1310 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::source-plugin ${lib.escapeShellArg "${viMotions}/motions.plugin.zsh"}
    fi
  '';
}
