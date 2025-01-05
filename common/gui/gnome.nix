{ lib, pkgs, ... }:
{
  services.xserver.desktopManager.gnome.enable = true;
  # power-profiles-daemon conflicts with tlp
  # https://linrunner.de/tlp/faq/ppd.html
  services.power-profiles-daemon.enable = lib.mkForce false;

  environment.gnome.excludePackages = (
    with pkgs;
    [
      # evince # document viewer
      # gnome-characters
      atomix # puzzle game
      cheese # webcam tool
      epiphany # web browser
      geary # email reader
      gedit # text editor
      gnome-music
      gnome-photos
      gnome-terminal
      gnome-tour
      hitori # sudoku game
      iagno # go game
      tali # poker game
      totem # video player
    ]
  );
}
