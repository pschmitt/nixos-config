{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # terraform # 1.6+
    (writeShellScriptBin "terraform-unfree" ''
      ${pkgs.terraform}/bin/terraform "$@"
    '')
    pkgs.terraform-157.terraform
    terragrunt
    openbao
    opentofu
    vendir
    vault
  ];
}
