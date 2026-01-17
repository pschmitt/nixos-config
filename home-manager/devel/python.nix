{ pkgs, ... }:
{
  home.packages = with pkgs; [
    black
    isort
    pipx
    # poetry
    python3Packages.flake8
    python3Packages.ipython
    uv

    (python3.withPackages (
      ps: with ps; [
        dbus-python
        gst-python
        pygobject3
        requests
        rich
      ]
    ))
  ];
}
