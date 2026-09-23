{ lib, ... }:
{
  options.services.luks-ssh-unlock-fleet = {
    selfKeyPath = lib.mkOption {
      type = lib.types.path;
      default = "/home/pschmitt/.ssh/id_ed25519";
      description = ''
        SSH private key this host authenticates as when unlocking other fleet
        members. Cloud hosts that shouldn't hold a copy of the personal key
        override this with a dedicated identity instead (see
        hosts/rofl-10/default.nix).
      '';
    };

    targetNames = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = ''
        Fleet targets to unlock. When null, unlock all other fleet members.
      '';
    };

    jumpHost = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            hostname = lib.mkOption {
              type = lib.types.str;
              description = "Hostname of the SSH jump host.";
            };
            username = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "SSH username for the jump host.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 22;
              description = "SSH port on the jump host.";
            };
            key = lib.mkOption {
              type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
              default = null;
              description = "Optional SSH private key for the jump host.";
            };
          };
        }
      );
      default = null;
      description = "Optional SSH jump host used to reach fleet targets.";
    };
  };
}
