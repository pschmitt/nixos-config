{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # terraform # 1.6+
    (writeShellScriptBin "terraform-unfree" ''
      ${pkgs.terraform}/bin/terraform "$@"
    '')
    pkgs.terraform-157.terraform
    terragrunt
    # FIXME openbao is broken (2026-01-09)
    # https://github.com/NixOS/nixpkgs/pull/478004
    openbao
    opentofu
    vendir
    vault
  ];
}
