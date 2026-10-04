{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginPath;
  manydots = pkgs.fetchFromGitHub {
    owner = "knu";
    repo = "zsh-manydots-magic";
    rev = "4372de0718714046f0c7ef87b43fc0a598896af6";
    hash = "sha256-lv7e7+KBR/nxC43H0uvphLcI7fALPvxPSGEmBn0g8HQ=";
  };
in
{
  programs.zsh.initContent = lib.mkOrder 946 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::source-plugin ${pluginPath "manydots" "manydots-magic" "${manydots}/manydots-magic"}
    fi
  '';
}
