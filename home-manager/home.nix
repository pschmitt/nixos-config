{
  lib,
  osConfig,
  ...
}:
{
  imports = lib.concatLists [
    (
      [
        ./common.nix
      ]
      ++ import ./main-modules.nix { develModule = ./devel; }
      ++ [
        # ./openclaw.nix
        ./gpg.nix
        ./sops.nix
        ./ssh.nix
        ./work
        ./yadm.nix
      ]
    )
    (lib.optional osConfig.hardware.bluetooth.enable ./bluetooth.nix)
    (lib.optional osConfig.services.xserver.enable ./gui)
  ];

  home = {
    # The home.stateVersion option does not have a default and must be set
    inherit (osConfig.system) stateVersion;
  };
}
