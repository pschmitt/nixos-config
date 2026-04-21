{ ... }:
{
  imports = [
    ../server-base.nix
    ../sops-standalone.nix
  ];

  sops.defaultSopsFile = ../../hosts/fnuc/secrets.sops.yaml;

  targets.genericLinux.enable = true;

  home = {
    username = "pschmitt";
    homeDirectory = "/home/pschmitt";
    stateVersion = "25.11";
  };
}
