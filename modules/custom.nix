{ lib, ... }:

{
  options = {
    custom.username = lib.mkOption {
      type = lib.types.str;
      default = "pschmitt";
      description = "Main user's username.";
    };

    custom.email = lib.mkOption {
      type = lib.types.str;
      default = "philipp@schmitt.co";
      description = "Main user email address.";
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

    custom.authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        let
          authorizedKeysContent = lib.strings.fileContents (builtins.fetchurl {
            url = "https://github.com/pschmitt.keys";
            sha256 = "0qcixq2zsh6p4xzxmjdl7bh13wyyv479sxhb0g2qg0qa6wg6qa49";
          });
        in
        lib.splitString "\n" authorizedKeysContent;
      description = "Main SSH authorized keys file";
    };

    custom.server = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether or not this is a server";
    };

    custom.useBIOS = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use BIOS instead of UEFI";
    };
  };
}
