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

    custom.authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        let
          authorizedKeysContent = lib.strings.fileContents (builtins.fetchurl {
            url = "https://github.com/pschmitt.keys";
            sha256 = "082ck5qhyswbinif0b0rb0n26i6m5rkvx6plhdsili3dyx5l7dqc";
          });
        in
        lib.filter (key: key != "") (lib.splitString "\n" authorizedKeysContent);
      description = "Main SSH authorized keys file";
    };
  };
}
