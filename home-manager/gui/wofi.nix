# wofi launcher and its config (formerly in yadm)
{ pkgs, ... }:
{
  home.packages = [ pkgs.wofi ];

  xdg.configFile."wofi" = {
    source = ./wofi;
    recursive = true;
  };
}
