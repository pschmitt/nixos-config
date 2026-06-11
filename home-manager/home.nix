{
  config,
  lib,
  # Import-gating facts come via specialArgs (set by the NixOS bridge in
  # ./default.nix; defaulted here for standalone hosts) to avoid a
  # config-in-imports infinite recursion.
  guiEnable ? false,
  bluetoothEnable ? false,
  ...
}:
{
  imports = lib.concatLists [
    [
      ./base.nix
      # ./openclaw.nix
      ./sops.nix
      ./ssh.nix
      ./work
      ./yadm.nix
    ]
    (lib.optional bluetoothEnable ./bluetooth.nix)
    (lib.optional guiEnable ./gui)
  ];

  # The home.stateVersion option does not have a default and must be set
  home.stateVersion = config.host.stateVersion;
}
