# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{
  pkgs ? (import ../nixpkgs.nix) { },
  inputs ? null,
}:

let
  font-resizer = pkgs.python3Packages.callPackage ./fonts/font-resizer { };
  # libcaption = pkgs.callPackage ./libcaption { };
  # Hoisted so obs-control can depend on them (not top-level nixpkgs attrs).
  emoji-fzf = pkgs.callPackage ./emoji-fzf { };
  soundboard = pkgs.callPackage ./local/soundboard { };
  timew-status = pkgs.callPackage ./local/timew-status { };
  osd = pkgs.callPackage ./local/osd { };
  ComicCodeNF = pkgs.callPackage ./fonts/ComicCodeNF { inherit font-resizer; };
in
{
  # local pkgs
  bluez-headset-callback = pkgs.callPackage ./local/bluez-headset-callback { inherit osd; };
  custom-keymaps = pkgs.callPackage ./local/custom-keymaps { };
  dms-shell-critical-notifications = pkgs.callPackage ./local/dms-shell-critical-notifications {
    inherit inputs;
  };
  dms-timewarrior = pkgs.callPackage ./local/dms-timewarrior { inherit timew-status; };
  noctalia-timewarrior = pkgs.callPackage ./local/noctalia-timewarrior { inherit timew-status; };
  noctalia-battery-icon = pkgs.callPackage ./local/noctalia-battery-icon { inherit ComicCodeNF; };
  noctalia-syncthing = pkgs.callPackage ./local/noctalia-syncthing { };
  ai-usagebar = pkgs.callPackage ./local/ai-usagebar { };
  docker-compose-wrapper = pkgs.callPackage ./local/docker-compose-wrapper { };
  ms-teams = pkgs.callPackage ./local/ms-teams { inherit inputs; };
  inherit osd;
  obs-control = pkgs.callPackage ./local/obs-control {
    inherit
      inputs
      emoji-fzf
      soundboard
      osd
      ;
    inherit (pkgs) walker;
  };
  quickshell-bar = pkgs.callPackage ./local/quickshell-bar { inherit timew-status; };
  inherit soundboard;
  syncshell-dank-widget = pkgs.callPackage ./local/syncshell-dank-widget { inherit inputs; };
  systemctl-service-exec = pkgs.callPackage ./local/systemctl-service-exec { };
  inherit timew-status;
  udev-custom-callback = pkgs.callPackage ./local/udev-custom-callback { };
  walker-menu = pkgs.callPackage ./local/walker-menu {
    inherit emoji-fzf soundboard;
  };

  # external pkgs
  cdpcurl = pkgs.callPackage ./cdpcurl { };
  clipcascade = pkgs.callPackage ./clipcascade { };
  inherit emoji-fzf;
  firefox-devtools-mcp = pkgs.callPackage ./firefox-devtools-mcp { };
  go-hass-agent = pkgs.callPackage ./go-hass-agent { };
  happy-hacking-gnu = pkgs.callPackage ./happy-hacking-gnu { };
  hyprevents = pkgs.callPackage ./hyprevents { };
  immich-face-to-album = pkgs.callPackage ./immich-face-to-album { };
  jsonrepair = pkgs.callPackage ./jsonrepair { };
  ketall = pkgs.callPackage ./ketall { };
  libfprint-focaltech = pkgs.callPackage ./libfprint-focaltech { };
  linkding-cli = pkgs.callPackage ./linkding-cli { };
  lnxlink = pkgs.python3Packages.callPackage ./lnxlink { };
  mmonit = pkgs.callPackage ./mmonit { };
  native-client = pkgs.callPackage ./native-client { };
  opsgenie-cli = pkgs.callPackage ./opsgenie-cli { };
  playconsole-cli = pkgs.callPackage ./playconsole-cli { };
  shellyctl = pkgs.callPackage ./shellyctl { };
  ssh-clipboard = pkgs.callPackage ./ssh-clipboard { };
  still = pkgs.callPackage ./still { };
  stui = pkgs.callPackage ./stui { };
  syncthingtui = pkgs.callPackage ./syncthingtui { };
  tewi = pkgs.callPackage ./tewi { };
  timewarrior-jirapush = pkgs.callPackage ./timewarrior-jirapush { };
  todoist-cli = pkgs.callPackage ./todoist-cli { };
  waypoint = pkgs.callPackage ./waypoint { };
  withoutbg = pkgs.python3Packages.callPackage ./withoutbg { };
  yank-osc52 = pkgs.callPackage ./yank-osc52 { };

  # oci pkgs
  oci-consistent-device-naming = pkgs.callPackage ./oci/oci-consistent-device-naming { };
  oracle-cloud-agent = pkgs.callPackage ./oci/oracle-cloud-agent { };

  # Fonts
  ComicCode = pkgs.callPackage ./fonts/ComicCode { };
  inherit ComicCodeNF;
  MonoLisa = pkgs.callPackage ./fonts/MonoLisa { };
  MonoLisaNF = pkgs.callPackage ./fonts/MonoLisaNF { };
  MonoLisa-Custom = pkgs.callPackage ./fonts/MonoLisa-Custom { };
  MonoLisa-CustomNF = pkgs.callPackage ./fonts/MonoLisa-CustomNF { };

  # OBS Studio
  # obs-studio-plugins.obs-freeze-filter = pkgs.qt6Packages.callPackage ./obs-studio/plugins/obs-freeze-filter { };
  # obs-studio-plugins.obs-replay-source = pkgs.qt6Packages.callPackage ./obs-studio/plugins/obs-replay-source { inherit libcaption; };

  tmux-mcp = pkgs.callPackage ./tmux-mcp { };

  # Lab
  davcli = pkgs.callPackage ./davcli { };
  qs-hyprview = pkgs.callPackage ./qs-hyprview { };
  quickshell-overview = pkgs.callPackage ./quickshell-overview { };
  # netbird-dashboard = pkgs.callPackage ./netbird-dashboard { };

  falcon-sensor-wiit = pkgs.callPackage ./falcon-sensor-wiit { inherit inputs; };
}
