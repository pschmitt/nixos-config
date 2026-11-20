# Terminal emulator configs (formerly in yadm); the packages come from the
# NixOS desktop profile (profiles/features/desktop/apps.nix). kitty has its
# own module (./kitty.nix).
{ lib, ... }:
{
  xdg.configFile = lib.genAttrs [ "alacritty" "foot" "wezterm" ] (name: {
    source = ./terminals + "/${name}";
    recursive = true;
  });
}
