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
    (writeShellScriptBin "kubectl-1.23" ''
      ${pkgs.kubectl-123.kubectl}/bin/kubectl "$@"
    '')
    kubectl-neat
    kubectl-rook-ceph
    kubernetes-helm
    rancher
    skopeo
    sonobuoy
    stern
    velero
  ];
}
