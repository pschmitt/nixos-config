{ config, pkgs, ... }:
let
  signalStack = pkgs.stdenv.mkDerivation {
    pname = "full-nix-eza-signal-stack";
    version = "1";
    src = ./eza-stack.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -shared -fPIC -O2 -Wall -Wextra -Werror "$src" -o stack.so
    '';
    installPhase = ''
      install -Dm755 stack.so $out/lib/stack.so
    '';
  };
in
{
  home.packages = [ config.programs.eza.package ];
  programs.eza.package = pkgs.symlinkJoin {
    name = "eza-full-nix";
    paths = [ pkgs.eza ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/eza --prefix LD_PRELOAD : ${signalStack}/lib/stack.so
    '';
  };
}
