{ pkgs, ... }:
{
  home.packages = with pkgs; [
    act # gh actions, locally
    diff-so-fancy
    gh
    git-extras
  ];
}
