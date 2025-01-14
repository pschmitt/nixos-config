{ pkgs, ... }:

{
  home.packages = with pkgs; [
    devenv
    inotify-tools
    git-extras
  ];
}
