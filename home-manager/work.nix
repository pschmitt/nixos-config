{ inputs, lib, config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Work
    acme-sh
    argocd-vault-plugin
    cmctl
    glab
    kubectl
    (writeShellScriptBin "kubectl-1.23" ''
      ${pkgs.kubectl-123.kubectl}/bin/kubectl "$@"
    '')
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
    (writeShellScriptBin "terraform-unfree" ''
      ${pkgs.terraform}/bin/terraform "$@"
    '')
    pkgs.terraform-157.terraform
    terragrunt
    opentofu
    thunderbird
    timewarrior
    timewarrior-jirapush
    vendir
    velero
    vault
    ytt
    zoom-us
  ];
}
