{ pkgs, ... }:

{
  home.packages = with pkgs; [
    devenv
    inotify-tools
    mani # manage multiple git repositories
  ];
}
