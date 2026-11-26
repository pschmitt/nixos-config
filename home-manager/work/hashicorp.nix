{ lib, pkgs, ... }:
let
  terraform = pkgs.terraform-157.terraform;
in
{
  home.packages = with pkgs; [
    # terraform # 1.6+
    (writeShellScriptBin "terraform-unfree" ''
      ${pkgs.terraform}/bin/terraform "$@"
    '')
    terraform
    terragrunt
    openbao
    opentofu
    vendir
    vault
  ];

  # Their completions are the binaries themselves (bash `complete -C`), after
  # compinit/bashcompinit (config/completions.nix, order 1000).
  programs.zsh.initContent = lib.mkOrder 1020 ''
    if [[ -z "''${NO_COMPLETIONS:-}" ]]
    then
      complete -o nospace -C ${lib.getExe' terraform "terraform"} terraform
      complete -o nospace -C ${lib.getExe' pkgs.vault "vault"} vault
      complete -o nospace -C ${lib.getExe' pkgs.openbao "bao"} bao
    fi
  '';
}
