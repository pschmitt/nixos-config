{ pkgs, ... }:
{
  imports = [
    ./bin
    ./conf
    ./plugins
    ./services
    ./waybar
  ];

  home.packages = [
    pkgs.hyprevents
  ];
}
