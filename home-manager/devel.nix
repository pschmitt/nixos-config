{ pkgs, ... }:

{
  home.packages = with pkgs; [
    act # gh actions, locally
    devenv
    gh
    git-extras
    inotify-tools
  ];
}
