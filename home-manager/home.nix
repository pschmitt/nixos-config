{
  config,
  inputs,
  lib,
  # Import-gating facts come via specialArgs (set by the NixOS bridge in
  # ./default.nix) to avoid a config-in-imports infinite recursion.
  guiEnable ? false,
  bluetoothEnable ? false,
  ...
}:
{
  imports = lib.concatLists [
    [
      ./base.nix
      # services.browser-daemon-local (the local tab API's server); only
      # declares options until a host enables it (browser node hosts do).
      inputs.browser-daemon.homeManagerModules.default
      ./sops.nix
      ./ssh.nix
      inputs.nixos-config-private.homeManagerModules.kubeconfigSnapshot
      inputs.nixos-config-private.homeManagerModules.sshClient
      inputs.nixos-config-private.homeManagerModules.zshFiles
      ./ssh-clipboard.nix
      ./work
      ./yadm.nix
    ]
    (lib.optional bluetoothEnable ./bluetooth.nix)
    (lib.optional guiEnable ./tracker.nix)
    (lib.optional guiEnable ./gui)
  ];

  # The home.stateVersion option does not have a default and must be set
  home.stateVersion = config.host.stateVersion;
}
