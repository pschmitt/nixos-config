{ lib, ... }:

{
  options.mainUser = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "pschmitt";
      description = "Main user's username.";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      default = "Philipp Schmitt";
      description = "Main user's full name.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "philipp@schmitt.co";
      description = "Main user email address.";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/home/pschmitt";
      description = "Main user's home directory.";
    };

    sshKey = lib.mkOption {
      type = lib.types.path;
      default = "/home/pschmitt/.ssh/id_ed25519";
      description = "Main SSH key (used for age decryption)";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        let
          authorizedKeysContent = lib.strings.fileContents (
            builtins.fetchurl {
              url = "https://github.com/pschmitt.keys";
              sha256 = "sha256:1ivxad3y66bxsga5w6bwq74fgga5dahljyjc6digkgs6vqlw6p9f";
            }
          );
        in
        lib.splitString "\n" authorizedKeysContent;
      description = "Main SSH authorized keys file";
    };

    extraAuthorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # hass-fnuc
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7"
      ];
      description = "Authorized keys not sourced from GitHub (e.g. internal service keys).";
    };
  };
}
