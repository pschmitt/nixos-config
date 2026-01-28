{ pkgs, ... }:
{
  home.packages = with pkgs; [
    argocd
    argocd-vault-plugin
    cmctl
    ketall # kubectl get-all
    kbld
    krew
    kubecolor
    kubeconform
    kubectl
    (writeShellScriptBin "kubectl-1.23" ''
      ${pkgs.kubectl-123.kubectl}/bin/kubectl "$@"
    '')
    kubectl-neat
    kubectl-rook-ceph
    kubernetes-helm
    kustomize
    ksops
    rancher
    skopeo
    sonobuoy
    stern
    velero
  ];

  # Kustomize exec plugins are discovered under $XDG_CONFIG_HOME/kustomize/plugin
  # with a group/version/kind layout; symlink ksops here so kustomize can find it.
  home.file.".config/kustomize/plugin/viaduct.ai/v1/ksops/ksops".source = "${pkgs.ksops}/bin/ksops";
}
