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
}
