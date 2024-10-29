# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{
  pkgs ? (import ../nixpkgs.nix) { },
}:

let
  font-resizer = pkgs.python3Packages.callPackage ./fonts/font-resizer { };
  # libcaption = pkgs.callPackage ./libcaption { };
  obsws-python = pkgs.python3Packages.callPackage ./obs-studio/obsws-python { };
  myl-discovery = pkgs.python3Packages.callPackage ./myl-discovery { };
in
{
  bluez-headset-callback = pkgs.callPackage ./bluez-headset-callback { };
  docker-compose-bulk = pkgs.callPackage ./docker-compose-bulk { };
  emoji-fzf = pkgs.callPackage ./emoji-fzf { };
  flarectl = pkgs.callPackage ./flarectl { };
  hacompanion = pkgs.callPackage ./hacompanion { };
  happy-hacking-gnu = pkgs.callPackage ./happy-hacking-gnu { };
  immich-face-to-album = pkgs.callPackage ./immich-face-to-album { };
  jsonrepair = pkgs.callPackage ./jsonrepair { };
  ldifj = pkgs.callPackage ./ldifj { };
  lan-mouse = pkgs.callPackage ./lan-mouse { };
  luks-mount = pkgs.callPackage ./luks-mount { };
  luks-ssh-unlock = pkgs.callPackage ./luks-ssh-unlock { };
  mmonit = pkgs.callPackage ./mmonit { };
  myl = pkgs.callPackage ./myl { inherit myl-discovery; };
  myl-discovery = pkgs.callPackage ./myl-discovery { };
  oci-consistent-device-naming = pkgs.callPackage ./oci-consistent-device-naming { };
  oracle-cloud-agent = pkgs.callPackage ./oracle-cloud-agent { };
  obs-cli = pkgs.python3Packages.callPackage ./obs-studio/obs-cli/default.nix {
    inherit obsws-python;
  };
  obs-studio-plugins-flatpak-obs-text-pango-bin =
    pkgs.qt6Packages.callPackage ./obs-studio/plugins/flatpak/obs-text-pango-bin
      { };
  obs-studio-plugins-flatpak-obs-text-pthread-bin =
    pkgs.qt6Packages.callPackage ./obs-studio/plugins/flatpak/obs-text-pthread-bin
      { };
  obs-studio-plugins-flatpak-obs-freeze-filter-bin =
    pkgs.qt6Packages.callPackage ./obs-studio/plugins/flatpak/obs-freeze-filter-bin
      { };
  obs-studio-plugins-flatpak-obs-replay-source-bin =
    pkgs.qt6Packages.callPackage ./obs-studio/plugins/flatpak/obs-replay-source-bin
      { };
  # obs-studio-plugins.obs-freeze-filter = pkgs.qt6Packages.callPackage ./obs-studio/plugins/obs-freeze-filter { };
  # obs-studio-plugins.obs-replay-source = pkgs.qt6Packages.callPackage ./obs-studio/plugins/obs-replay-source { inherit libcaption; };
  timewarrior-jirapush = pkgs.callPackage ./timewarrior-jirapush { };
  tmux-slay = pkgs.callPackage ./tmux-slay { };
  udev-custom-callback = pkgs.callPackage ./udev-custom-callback { };

  # Fonts
  ComicCode = pkgs.callPackage ./fonts/ComicCode { };
  ComicCodeNF = pkgs.callPackage ./fonts/ComicCodeNF { inherit font-resizer; };
  MonoLisa = pkgs.callPackage ./fonts/MonoLisa { };
  MonoLisaNF = pkgs.callPackage ./fonts/MonoLisaNF { };
  MonoLisa-Custom = pkgs.callPackage ./fonts/MonoLisa-Custom { };
  MonoLisa-CustomNF = pkgs.callPackage ./fonts/MonoLisa-CustomNF { };

  # Lab
  pyghmi = pkgs.callPackage ./pyghmi { };
  vdhcoapp = pkgs.callPackage ./vdhcoapp { };
}
