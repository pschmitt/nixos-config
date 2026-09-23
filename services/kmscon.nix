{ lib, pkgs, ... }:
{
  services.kmscon = {
    enable = lib.mkDefault true;
    config = {
      hwaccel = lib.mkDefault true;
      "font-name" = lib.mkDefault "Comic Code";
      "grab-reboot" = lib.mkDefault "<Ctrl><Alt>Delete";
    };
  };

  fonts.packages = [ pkgs.ComicCode ];
  hardware.graphics.enable = lib.mkDefault true;
}
