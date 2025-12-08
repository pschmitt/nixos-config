{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./browser.nix
    ./devel.nix
    ./gui.nix
    ./hashicorp.nix
    ./jcalapi.nix
    ./k8s.nix
    ./timetracking.nix
  ];

  home.packages = with pkgs; [
    # acme
    acme-sh
    lego

    # azure ad etc
    master.azure-cli
    master.azure-cli-extensions.ad
    master.azure-cli-extensions.fzf
    inputs.ldifj.packages.${pkgs.stdenv.hostPlatform.system}.default
    openldap

    # misc
    ipmitool
    jira-cli-go
    opsgenie-cli
    openvpn

    # cloud
    openstackclient-full
  ];

}
