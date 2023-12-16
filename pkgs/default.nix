# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{ pkgs ? (import ../nixpkgs.nix) { } }:

let
  font-resizer = pkgs.python3Packages.callPackage ./fonts/font-resizer { };
  libcaption = pkgs.callPackage ./libcaption { };
  obsws-python = pkgs.python3Packages.callPackage ./obsws-python { };
in
{
  distrobox = pkgs.callPackage ./distrobox { };
  flarectl = pkgs.callPackage ./flarectl { };
  hacompanion = pkgs.callPackage ./hacompanion { };
  happy-hacking-gnu = pkgs.callPackage ./happy-hacking-gnu { };
  jsonrepair = pkgs.callPackage ./jsonrepair { };
  ldifj = pkgs.callPackage ./ldifj { };
  obs-cli = pkgs.python3Packages.callPackage ./obs-cli { inherit obsws-python; };
  obs-studio-plugins.obs-freeze-filter = pkgs.qt6Packages.callPackage ./obs-studio-plugins.obs-freeze-filter { };
  obs-studio-plugins.obs-replay-source = pkgs.qt6Packages.callPackage ./obs-studio-plugins.obs-replay-source { inherit libcaption; };
  timewarrior-jirapush = pkgs.callPackage ./timewarrior-jirapush { };
  udev-custom-callback = pkgs.callPackage ./udev-custom-callback { };
  wezterm-bin = pkgs.callPackage ./wezterm/wezterm-bin { };
  wezterm-nightly = pkgs.callPackage ./wezterm/wezterm-nightly { };
  wezterm-nightly-appimage = pkgs.callPackage ./wezterm/wezterm-nightly-appimage { };

  # Fonts
  ComicCode = pkgs.callPackage ./fonts/ComicCode { };
  ComicCodeNF = pkgs.callPackage ./fonts/ComicCodeNF { inherit font-resizer; };
  MonoLisa = pkgs.callPackage ./fonts/MonoLisa { };
  MonoLisaNF = pkgs.callPackage ./fonts/MonoLisaNF { };
  MonoLisa-Custom = pkgs.callPackage ./fonts/MonoLisa-Custom { };
  MonoLisa-CustomNF = pkgs.callPackage ./fonts/MonoLisa-CustomNF { };
}
