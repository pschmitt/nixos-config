{ pkgs, ... }:
{
  home.packages = with pkgs; [
    black
    isort
    pipx
    poetry
    python3Packages.flake8
    python3Packages.ipython
    uv
  ];
}
