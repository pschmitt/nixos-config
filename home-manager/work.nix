{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  # Conditional packages based on xserver.enabled
  guiPackages = lib.optionals osConfig.services.xserver.enable [
    pkgs.zoom-us
    pkgs.onlyoffice-bin
  ];
in
{
  home.packages =
    with pkgs;
    [
      # Work
      acme-sh
      argocd
      argocd-vault-plugin
      azure-cli
      cmctl
      glab
      kubectl
      (writeShellScriptBin "kubectl-1.21" ''
        ${pkgs.kubectl-121.kubectl}/bin/kubectl "$@"
      '')
      (writeShellScriptBin "kubectl-1.23" ''
        ${pkgs.kubectl-123.kubectl}/bin/kubectl "$@"
      '')
      kubernetes-helm
      ipmitool
      ldifj
      lefthook
      lego
      httptunnel
      chisel
      corkscrew
      oci-cli
      openldap
      openstackclient-full
      openvpn
      rclone
      s3cmd
      skopeo
      stern
      sqlfluff
      taskwarrior3
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
    ]
    ++ guiPackages;
}
