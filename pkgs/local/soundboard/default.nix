# Nix-native replacement for the zhj-backed soundboard:: zsh helpers.
{
  lib,
  writeShellApplication,
  pipewire, # pw-play, pw-link, pw-dump, pw-cli
  pulseaudio, # pactl
  jq,
  gnugrep,
  gawk,
  coreutils,
  psmisc, # killall
}:
writeShellApplication {
  name = "soundboard";
  runtimeInputs = [
    pipewire
    pulseaudio
    jq
    gnugrep
    gawk
    coreutils
    psmisc
  ];
  text = builtins.readFile ./soundboard.sh;
  meta = {
    description = "Local soundboard playback + PipeWire routing (replaces soundboard:: zsh helpers)";
    platforms = lib.platforms.linux;
    mainProgram = "soundboard";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}
