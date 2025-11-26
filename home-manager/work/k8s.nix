{ pkgs, ... }:
{
  home.packages = with pkgs; [
    argocd
    argocd-vault-plugin
    cmctl
    ketall # kubectl get-all
    krew
    kubecolor
    kubectl
    (writeShellScriptBin "kubectl-1.21" ''
      ${pkgs.kubectl-121.kubectl}/bin/kubectl "$@"
    '')
    (writeShellScriptBin "kubectl-1.23" ''
      ${pkgs.kubectl-123.kubectl}/bin/kubectl "$@"
    '')
    kubectl-neat
    kubectl-rook-ceph
    kubernetes-helm
    rancher
    skopeo
    stern
    velero
  ];
}
