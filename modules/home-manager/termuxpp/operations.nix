{ pkgs, ... }:
{
  home.packages = builtins.attrValues {
    inherit (pkgs)
      age
      ansible
      dnsutils
      gh
      glab
      iproute2
      k9s
      kubecolor
      kubeconform
      kubectl
      kubectl-neat
      kubelogin-oidc
      kubernetes-helm
      kustomize
      openstackclient-full
      openstack-rs
      opentofu
      stern
      yq-go
      ;
  };
}
