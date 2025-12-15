{
  lib,
  pkgs,
  ...
}:

let
  # XXX Disable AppImage support on non-x86_64 platforms for now
  # Blame:
  # https://github.com/NixOS/nixpkgs/commit/d151f99d0f0c460b2f5344c58a4e1b759b7dffcd
  enableAppImage = pkgs.stdenv.hostPlatform.isx86_64;
in
lib.mkIf enableAppImage {
  programs.appimage = {
    enable = true;
    binfmt = true;
  };
}
