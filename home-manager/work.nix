{ inputs, lib, config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Work
    acme-sh
    cmctl
    glab
    kubectl
    kubernetes-helm
    lefthook
    lego
    httptunnel
    chisel
    corkscrew
    onlyoffice-bin
    openconnect
    openldap
    openstackclient-with-designate
    openvpn
    rclone
    s3cmd
    skopeo
    stern
    taskwarrior
    terraform
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
