{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  options.fullNix.rooted = lib.mkEnableOption "using native Android su for network queries on a rooted device";

  config = {
    home.packages = [
      ((inputs.termuxpp.lib.nixpp.packagesFor pkgs).termuxpp-ip.override {
        inherit (config.fullNix) rooted;
      })
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
  };
}
