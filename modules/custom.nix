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
  };
}
