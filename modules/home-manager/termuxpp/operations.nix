{ pkgs, ... }:
{
  home.packages = [
    (pkgs.callPackage ../../../pkgs/nixpp/ip.nix { })
  ]
  ++ builtins.attrValues {
    inherit (pkgs)
      age
      ansible
      dnsutils
      gh
      glab
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
