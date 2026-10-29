# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example' or (legacy) 'nix-build -A example'

{
  pkgs ? (import ../nixpkgs.nix) { },
  inputs ? null,
}:

let
  # The flake's packages output imports this file without overlays, so
  # pkgs.stable only exists when called through the overlay.
  stablePkgs = pkgs.stable or inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  zsh-tools = pkgs.callPackage ./zsh-tools { inherit inputs; };
  font-resizer = pkgs.python3Packages.callPackage ./fonts/font-resizer { };
  # Hoisted so obs-control can depend on them (not top-level nixpkgs attrs).
  emoji-fzf = pkgs.callPackage ./emoji-fzf { };
  soundboard = pkgs.callPackage ./local/soundboard { };
  timew-is-on = pkgs.callPackage ./local/timew-is-on { };
  timew-total = pkgs.callPackage ./local/timew-total { };
  timew-status = pkgs.callPackage ./local/timew-status {
    inherit timew-is-on timew-total;
  };
  osd = pkgs.callPackage ./local/osd { };
  screencast-state = pkgs.callPackage ./local/screencast-state { };
  ComicCodeNF = pkgs.callPackage ./fonts/ComicCodeNF { inherit font-resizer; };
  oci-consistent-device-naming = pkgs.callPackage ./oci/oci-consistent-device-naming { };
in
{
  # local pkgs
  bluez-headset-callback = pkgs.callPackage ./local/bluez-headset-callback { inherit osd; };
  caffeine = pkgs.callPackage ./local/caffeine { };
  custom-keymaps = pkgs.callPackage ./local/custom-keymaps { };
  codexbar = pkgs.callPackage ./local/codexbar { };
  ms-teams = pkgs.callPackage ./local/ms-teams { inherit inputs; };
  mullvad-expiration = pkgs.callPackage ./local/mullvad-expiration { };
  inherit osd;
  fzf-preview = pkgs.callPackage ./local/fzf-preview { };
  ldif2json = pkgs.callPackage ./local/ldif2json { };
  pinentry-guess = pkgs.callPackage ./local/pinentry-guess { };
  pycolumn = pkgs.callPackage ./local/pycolumn { };
  update-and-deploy = pkgs.callPackage ./local/update-and-deploy { };
  obs-control = pkgs.callPackage ./local/obs-control {
    inherit
      inputs
      emoji-fzf
      soundboard
      osd
      ;
    inherit (pkgs) walker;
  };
  inherit screencast-state;
  inherit soundboard;
  xcp = pkgs.callPackage ./local/xcp { };
  zebra = pkgs.callPackage ./local/zebra { };
  zhj = pkgs.callPackage ./local/zhj { };
  systemctl-service-exec = pkgs.callPackage ./local/systemctl-service-exec { };
  inherit
    timew-is-on
    timew-status
    timew-total
    ;
  walker-menu = pkgs.callPackage ./local/walker-menu {
    inherit emoji-fzf soundboard;
  };
  ha-walker = pkgs.callPackage ./local/ha-walker { };

  browser-daemon = inputs.browser-daemon.packages.${pkgs.stdenv.hostPlatform.system}.default;
  cdpcurl = pkgs.callPackage ./cdpcurl { };
  inherit emoji-fzf;
  go-hass-agent = pkgs.callPackage ./go-hass-agent { };
  hyprland-share-picker-gtk = pkgs.callPackage ./hyprland-share-picker-gtk { };
  hyprevents = pkgs.callPackage ./hyprevents { };
  # Hypruse 0.13 requires MCP 1.x; the unstable package set now has MCP 2.x.
  hypruse = stablePkgs.python3Packages.callPackage ./hypruse {
    inherit (pkgs)
      grim
      hyprland
      systemd
      wl-clipboard
      wtype
      ;
  };
  immich-face-to-album = pkgs.callPackage ./immich-face-to-album { };
  immich-mcp = pkgs.callPackage ./immich-mcp { };
  jsonrepair = pkgs.callPackage ./jsonrepair { };
  ketall = pkgs.callPackage ./ketall { };
  libfprint-focaltech = pkgs.callPackage ./libfprint-focaltech { };
  linkding-cli = pkgs.callPackage ./linkding-cli { };
  lumine-capture = pkgs.callPackage ./lumine-capture { };
  lnxlink = pkgs.python3Packages.callPackage ./lnxlink { };
  mmonit = pkgs.callPackage ./mmonit { };
  nixpp-termux = pkgs.callPackage ./termux/nixpp { inherit inputs; };
  native-client = pkgs.callPackage ./native-client { };
  opsgenie-cli = pkgs.callPackage ./opsgenie-cli { };
  playconsole-cli = pkgs.callPackage ./playconsole-cli { };
  shellyctl = pkgs.callPackage ./shellyctl { };
  slack-mcp-server = pkgs.callPackage ./slack-mcp-server { };
  skills-ref = pkgs.callPackage ./skills-ref { };
  skills-lint = pkgs.callPackage ./skills-lint { };
  ssh-clipboard = pkgs.callPackage ./ssh-clipboard { };
  still = pkgs.callPackage ./still { };
  stui = pkgs.callPackage ./stui { };
  syncthingtui = pkgs.callPackage ./syncthingtui { };
  termux-apt-prefix-builder = pkgs.callPackage ./termux/apt-prefix-builder { };
  tewi = pkgs.callPackage ./tewi { };
  timewarrior-jirapush = pkgs.callPackage ./timewarrior-jirapush { };
  todoist-cli = pkgs.callPackage ./todoist-cli { };
  todoist-mcp = pkgs.callPackage ./todoist-mcp { };
  waypoint = pkgs.callPackage ./waypoint { };
  inherit (zsh-tools)
    kubectl-ksh
    kubectl-socks5-proxy
    kubectl-watch
    netbird-cli
    tesmart-cli
    zsh-diff-so-fancy
    ;
  withoutbg = pkgs.python3Packages.callPackage ./withoutbg { };
  yank-osc52 = pkgs.callPackage ./yank-osc52 { };

  # oci pkgs
  inherit oci-consistent-device-naming;
  oracle-cloud-agent = pkgs.callPackage ./oci/oracle-cloud-agent { };
  oci-kexec-installer-aarch64-linux =
    (pkgs.callPackage ./oci/oci-kexec-installer {
      inherit inputs oci-consistent-device-naming;
      system = "aarch64-linux";
    }).overrideAttrs
      (oldAttrs: {
        meta = (oldAttrs.meta or { }) // {
          platforms = [ "aarch64-linux" ];
        };
      });

  # Fonts
  ComicCode = pkgs.callPackage ./fonts/ComicCode { };
  inherit ComicCodeNF;
  MonoLisa = pkgs.callPackage ./fonts/MonoLisa { };
  MonoLisaNF = pkgs.callPackage ./fonts/MonoLisaNF { };
  MonoLisa-Custom = pkgs.callPackage ./fonts/MonoLisa-Custom { };
  MonoLisa-CustomNF = pkgs.callPackage ./fonts/MonoLisa-CustomNF { };

  tmux-mcp = pkgs.callPackage ./tmux-mcp { };
  tmux-mcp-compat = pkgs.callPackage ./tmux-mcp-compat { };

  quickshell-overview = pkgs.callPackage ./quickshell-overview { };

  falcon-sensor-wiit = pkgs.callPackage ./falcon-sensor-wiit { inherit inputs; };
}
