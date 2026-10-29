# Opt-out for the iPhone Duo-style battery/Wi-Fi indicator in the Noctalia
# bar (see ./noctalia.nix). Off everywhere for now; set to true to bring it back.
{ lib, ... }:
{
  options.programs.noctalia-duo-status.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether to show the pschmitt/duo-status widget in the Noctalia bar.";
  };
}
