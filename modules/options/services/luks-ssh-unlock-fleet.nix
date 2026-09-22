{ lib, ... }:
{
  options.services.luks-ssh-unlock-fleet.selfKeyPath = lib.mkOption {
    type = lib.types.path;
    default = "/home/pschmitt/.ssh/id_ed25519";
    description = ''
      SSH private key this host authenticates as when unlocking other fleet
      members. Cloud hosts that shouldn't hold a copy of the personal key
      override this with a dedicated identity instead (see
      hosts/rofl-10/default.nix).
    '';
  };
}
