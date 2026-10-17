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
  # Commands the yadm local plugins (qr, imagemagick, ocr) build on.
  home-manager.users.${config.mainUser.username}.home.packages = [
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
