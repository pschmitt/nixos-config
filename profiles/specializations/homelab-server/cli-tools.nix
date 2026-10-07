{ config, pkgs, ... }:
{
  # Commands the yadm local plugins (qr, imagemagick, ocr) build on.
  home-manager.users.${config.mainUser.username}.home.packages = [
    pkgs.imagemagick
    pkgs.qrencode
    (pkgs.tesseract.override {
      enableLanguages = [
        "deu"
        "eng"
        "fra"
      ];
    })
  ];
}
