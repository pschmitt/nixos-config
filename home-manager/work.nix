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
      oci-cli
      openconnect
      openldap
      openstackclient
      openvpn
      rclone
      s3cmd
      skopeo
      stern
      sqlfluff
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
    ]
    ++ guiPackages;
}
