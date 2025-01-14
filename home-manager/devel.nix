{ pkgs, ... }:

{
  home.packages = with pkgs; [
    devenv
    git-extras
    inotify-tools
  ];
}
