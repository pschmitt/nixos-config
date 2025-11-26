{
  pkgs,
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
    ldifj
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
