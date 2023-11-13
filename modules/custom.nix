{ lib, ... }:

{
  options = {
    custom.username = lib.mkOption {
      type = lib.types.str;
      default = "pschmitt";
      description = "Main user's username.";
    };

    custom.homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/pschmitt";
      description = "Main user's home directory.";
    };

    custom.sshKey = lib.mkOption {
      type = lib.types.str;
      default = "/home/pschmitt/.ssh/id_ed25519";
      description = "Main SSH key (used for age decryption)";
    };
  };
}
