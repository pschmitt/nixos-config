{ pkgs, ... }:

{
  home.packages = with pkgs; [
    devenv
    gh
    git-extras
    inotify-tools
  ];
}
