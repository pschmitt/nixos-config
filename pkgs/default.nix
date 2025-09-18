# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{
  pkgs ? (import ../nixpkgs.nix) { },
}:

let
  font-resizer = pkgs.python3Packages.callPackage ./fonts/font-resizer { };
  # libcaption = pkgs.callPackage ./libcaption { };
  obsws-python = pkgs.python3Packages.callPackage ./obs-studio/obsws-python { };
in
{
  bluez-headset-callback = pkgs.callPackage ./bluez-headset-callback { };
  docker-compose-wrapper = pkgs.callPackage ./docker-compose-wrapper { };
  emoji-fzf = pkgs.callPackage ./emoji-fzf { };
  flarectl = pkgs.callPackage ./flarectl { };
  go-hass-agent = pkgs.callPackage ./go-hass-agent { };
  happy-hacking-gnu = pkgs.callPackage ./happy-hacking-gnu { };
  immich-face-to-album = pkgs.callPackage ./immich-face-to-album { };
  jsonrepair = pkgs.callPackage ./jsonrepair { };
  ldifj = pkgs.callPackage ./ldifj { };
  luks-mount = pkgs.callPackage ./luks-mount { };
  luks-ssh-unlock = pkgs.callPackage ./luks-ssh-unlock { };
  mmonit = pkgs.callPackage ./mmonit { };
  oci-consistent-device-naming = pkgs.callPackage ./oci-consistent-device-naming { };
  oracle-cloud-agent = pkgs.callPackage ./oracle-cloud-agent { };

  # OBS Studio
  obs-cli = pkgs.python3Packages.callPackage ./obs-studio/obs-cli/default.nix {
    inherit obsws-python;
  };
  # obs-studio-plugins.obs-freeze-filter = pkgs.qt6Packages.callPackage ./obs-studio/plugins/obs-freeze-filter { };
  # obs-studio-plugins.obs-replay-source = pkgs.qt6Packages.callPackage ./obs-studio/plugins/obs-replay-source { inherit libcaption; };

  timewarrior-jirapush = pkgs.callPackage ./timewarrior-jirapush { };
  tmux-slay = pkgs.callPackage ./tmux-slay { };
  udev-custom-callback = pkgs.callPackage ./udev-custom-callback { };
  waypoint = pkgs.callPackage ./waypoint { };

  # Fonts
  ComicCode = pkgs.callPackage ./fonts/ComicCode { };
  ComicCodeNF = pkgs.callPackage ./fonts/ComicCodeNF { inherit font-resizer; };
  MonoLisa = pkgs.callPackage ./fonts/MonoLisa { };
  MonoLisaNF = pkgs.callPackage ./fonts/MonoLisaNF { };
  MonoLisa-Custom = pkgs.callPackage ./fonts/MonoLisa-Custom { };
  MonoLisa-CustomNF = pkgs.callPackage ./fonts/MonoLisa-CustomNF { };

  # Lab
  cdpcurl = pkgs.callPackage ./cdpcurl { };
  native-client = pkgs.callPackage ./native-client { };
  osc = pkgs.callPackage ./osc { };
  pyghmi = pkgs.callPackage ./pyghmi { };
  # netbird-dashboard = pkgs.callPackage ./netbird-dashboard { };
}
