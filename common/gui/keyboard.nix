{ pkgs, ... }:
{
  imports = [
    ./keyd.nix
  ];
  # console.useXkbConfig = true;

  services.xserver.enable = true;
  services.xserver.xkb =
    let
      symbolsFile = name: "${pkgs.custom-keymaps}/share/X11/xkb/symbols/${name}";
    in
    {
      layout = "de";
      variant = "";

      extraLayouts = {
        hhkb-de = {
          description = "Custom HHKB DE layout by pschmitt";
          languages = [ "deu" ];
          symbolsFile = symbolsFile "hhkb-de";
        };
        gpdpocket4-us = {
          description = "GPD Pocket 4 layout with swapped Y/Z and AltGr tweaks";
          languages = [
            "eng"
            "deu"
          ];
          symbolsFile = symbolsFile "gpdpocket4-us";
        };
        gpdpocket4-de = {
          description = "GPD Pocket 4 custom DE Layout";
          languages = [ "deu" ];
          symbolsFile = symbolsFile "gpdpocket4-de";
        };
      };
    };
}
