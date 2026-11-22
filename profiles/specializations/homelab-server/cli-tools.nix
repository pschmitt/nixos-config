{
  config,
  lib,
  pkgs,
  ...
}:
let
  timg = pkgs.writeShellApplication {
    name = "timg";
    text = builtins.replaceStrings [ "@TIMG_BIN@" ] [ (lib.getExe pkgs.timg) ] (
      builtins.readFile ./scripts/timg.sh
    );
  };
in
{
  imports = [ ../../../services/circus/cli.nix ];

  home-manager.users.${config.mainUser.username}.home.packages = [
    # Commands the yadm local plugins (qr, imagemagick, ocr) build on.
    pkgs.imagemagick
    pkgs.qrencode
    timg
    (pkgs.tesseract.override {
      enableLanguages = [
        "deu"
        "eng"
        "fra"
      ];
    })
  ];
}
