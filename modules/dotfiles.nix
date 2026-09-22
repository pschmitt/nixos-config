{ lib, ... }:

{
  options.dotfiles.promptColor = lib.mkOption {
    type = lib.types.str;
    default = "white";
    description = "Main user's prompt color";
  };
}
