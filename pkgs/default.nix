# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{
  pkgs ? (import ../nixpkgs.nix) { },
}:

let
  font-resizer = pkgs.python3Packages.callPackage ./fonts/font-resizer { };
  # libcaption = pkgs.callPackage ./libcaption { };
in
{
  # local pkgs
  bluez-headset-callback = pkgs.callPackage ./local/bluez-headset-callback { };
  custom-keymaps = pkgs.callPackage ./local/custom-keymaps { };
  docker-compose-wrapper = pkgs.callPackage ./local/docker-compose-wrapper { };
  udev-custom-callback = pkgs.callPackage ./local/udev-custom-callback { };

  # external pkgs
  cdpcurl = pkgs.callPackage ./cdpcurl { };
  native-client = pkgs.callPackage ./native-client { };
  emoji-fzf = pkgs.callPackage ./emoji-fzf { };
  go-hass-agent = pkgs.callPackage ./go-hass-agent { };
  happy-hacking-gnu = pkgs.callPackage ./happy-hacking-gnu { };
  hyprevents = pkgs.callPackage ./hyprevents { };
  immich-face-to-album = pkgs.callPackage ./immich-face-to-album { };
  jsonrepair = pkgs.callPackage ./jsonrepair { };
  ketall = pkgs.callPackage ./ketall { };
  libfprint-focaltech = pkgs.callPackage ./libfprint-focaltech { };
  linkding-cli = pkgs.callPackage ./linkding-cli { };
  mmonit = pkgs.callPackage ./mmonit { };
  opsgenie-cli = pkgs.callPackage ./opsgenie-cli { };
  timewarrior-jirapush = pkgs.callPackage ./timewarrior-jirapush { };
  waypoint = pkgs.callPackage ./waypoint { };
  withoutbg = pkgs.python3Packages.callPackage ./withoutbg { };
  yank-osc52 = pkgs.callPackage ./yank-osc52 { };

  # custom packages, that should be flakes
  ldifj = pkgs.callPackage ./ldifj { };
  luks-mount = pkgs.callPackage ./luks-mount { };
  tmux-slay = pkgs.callPackage ./tmux-slay { };

  # oci pkgs
  oci-consistent-device-naming = pkgs.callPackage ./oci/oci-consistent-device-naming { };
  oracle-cloud-agent = pkgs.callPackage ./oci/oracle-cloud-agent { };

  # Fonts
  ComicCode = pkgs.callPackage ./fonts/ComicCode { };
  ComicCodeNF = pkgs.callPackage ./fonts/ComicCodeNF { inherit font-resizer; };
  MonoLisa = pkgs.callPackage ./fonts/MonoLisa { };
  MonoLisaNF = pkgs.callPackage ./fonts/MonoLisaNF { };
  MonoLisa-Custom = pkgs.callPackage ./fonts/MonoLisa-Custom { };
  MonoLisa-CustomNF = pkgs.callPackage ./fonts/MonoLisa-CustomNF { };

  # OBS Studio
  # obs-studio-plugins.obs-freeze-filter = pkgs.qt6Packages.callPackage ./obs-studio/plugins/obs-freeze-filter { };
  # obs-studio-plugins.obs-replay-source = pkgs.qt6Packages.callPackage ./obs-studio/plugins/obs-replay-source { inherit libcaption; };

  # Lab
  davcli = pkgs.callPackage ./davcli { };
  hints = pkgs.callPackage ./hints { };
  # netbird-dashboard = pkgs.callPackage ./netbird-dashboard { };
}
