# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{ pkgs ? (import ../nixpkgs.nix) { } }:

let
  libcaption = pkgs.callPackage ./libcaption { };
  obsws-python = pkgs.python3Packages.callPackage ./obsws-python { };
in
{
  comic-code = pkgs.callPackage ./comic-code { pkgSource = ""; };
  flarectl = pkgs.callPackage ./flarectl { };
  hacompanion = pkgs.callPackage ./hacompanion { };
  jsonrepair = pkgs.callPackage ./jsonrepair { };
  ldifj = pkgs.callPackage ./ldifj { };
  obs-cli = pkgs.python3Packages.callPackage ./obs-cli { inherit obsws-python; };
  obs-studio-plugins.obs-freeze-filter = pkgs.qt6Packages.callPackage ./obs-studio-plugins.obs-freeze-filter { };
  obs-studio-plugins.obs-replay-source = pkgs.qt6Packages.callPackage ./obs-studio-plugins.obs-replay-source { inherit libcaption; };
  timewarrior-jirapush = pkgs.callPackage ./timewarrior-jirapush { };
}
