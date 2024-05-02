{ config, pkgs, ... }:
{
  # See also:
  # https://github.com/nix-community/srvos/blob/main/nixos/roles/nix-remote-builder.nix
  users.users.nix-remote-builder = {
    isSystemUser = true;
    description = "User for remote builds (see common/global/nix-remote-build.nix)";
    group = "nix-remote-builder";
    shell = pkgs.bash;
    extraGroups = [
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICyWHQNmz85w1IPJIzmK6DFg2T0XOOazVjeymiaCb98 nix-remote-builder@nixos-config"
    ];
  };

  users.groups.nix-remote-builder = { };
  nix.settings.trusted-users = [ "nix-remote-builder" ];
}
