# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{ pkgs ? (import ../nixpkgs.nix) { } }:

let
  libcaption = pkgs.callPackage ./libcaption { };
in
{
  brotab = pkgs.callPackage ./brotab { };
  flarectl = pkgs.callPackage ./flarectl { };
  jsonrepair = pkgs.callPackage ./jsonrepair { };
  hacompanion = pkgs.callPackage ./hacompanion { };
  obs-studio-plugins.obs-freeze-filter = pkgs.qt6Packages.callPackage ./obs-studio-plugins.obs-freeze-filter { };
  obs-studio-plugins.obs-replay-source = pkgs.qt6Packages.callPackage ./obs-studio-plugins.obs-replay-source { inherit libcaption; };
  timewarrior-jirapush = pkgs.callPackage ./timewarrior-jirapush { };
}
