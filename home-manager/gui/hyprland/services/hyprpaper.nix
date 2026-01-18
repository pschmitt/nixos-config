{ config, ... }:
let
  wallpaperPath = "${config.home.homeDirectory}/Pictures/Wallpapers/chill.png";
in
{
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [ wallpaperPath ];
      wallpaper = [ "*,${wallpaperPath}" ];
    };
  };
}
