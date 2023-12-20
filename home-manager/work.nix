{ inputs, lib, config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Work
    acme-sh
    argocd-vault-plugin
    cmctl
    glab
    kubectl
    kubernetes-helm
    ldifj
    lefthook
    lego
    httptunnel
    chisel
    corkscrew
    onlyoffice-bin
    openconnect
    openldap
    openstackclient
    openvpn
    rclone
    s3cmd
    skopeo
    stern
    taskwarrior
    # terraform # 1.6+
    pkgs.terraform-157.terraform
    terragrunt
    opentofu
    thunderbird
    timewarrior
    timewarrior-jirapush
    vendir
    vault
    ytt
    zoom-us
  ];
}
