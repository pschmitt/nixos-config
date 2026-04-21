{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    defaultSopsFile = lib.mkDefault ../secrets/shared.sops.yaml;
    age = {
      generateKey = false;
      sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    };
  };
}
