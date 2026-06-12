# Nix-native replacement for the zhj-backed ~/bin/obs.zsh dispatcher.
{
  lib,
  stdenv,
  writeShellApplication,
  inputs,
  pulseaudio,
  v4l-utils,
  libnotify,
  jq,
  gnugrep,
  gawk,
  coreutils,
  emoji-fzf,
  wofi,
}:
let
  obs-cli = inputs.obs-cli.packages.${stdenv.hostPlatform.system}.obs-cli;
in
writeShellApplication {
  name = "obs-control";
  runtimeInputs = [
    obs-cli
    pulseaudio # pactl
    v4l-utils # v4l2-ctl
    libnotify # notify-send
    jq
    gnugrep
    gawk
    coreutils
    emoji-fzf
    wofi
  ];
  text = builtins.readFile ./obs-control.sh;
  meta = {
    description = "OBS Studio / mic / webcam control dispatcher (replaces ~/bin/obs.zsh)";
    platforms = lib.platforms.linux;
    mainProgram = "obs-control";
  };
}
