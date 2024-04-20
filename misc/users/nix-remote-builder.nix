{ config, ... }:
{
  users.users.nix-remote-builder = {
    uid = 10034;
    isNormalUser = true;
    description = "User for remote builds (see common/global/nix-remote-build.nix)";
    extraGroups = [
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICyWHQNmz85w1IPJIzmK6DFg2T0XOOazVjeymiaCb98 nix-remote-builder"
    ];
  };
}
