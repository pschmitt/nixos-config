{ pkgs, ... }:
{
  home.packages = with pkgs; [
    act # gh actions, locally
    diff-so-fancy
    gh
    glab
    git-extras
  ];
}
