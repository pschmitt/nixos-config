# Nix-native port of the tractable wofi.zsh menus (run / emoji / soundboard).
{
  lib,
  writeShellApplication,
  wofi,
  emoji-fzf,
  soundboard,
  libnotify, # notify-send
  wl-clipboard, # wl-copy
  glib, # gsettings
  gawk,
  gnused,
  gnugrep,
  coreutils,
  psmisc, # killall
}:
writeShellApplication {
  name = "wofi-menu";
  runtimeInputs = [
    wofi
    emoji-fzf
    soundboard
    libnotify
    wl-clipboard
    glib
    gawk
    gnused
    gnugrep
    coreutils
    psmisc
  ];
  text = builtins.readFile ./wofi-menu.sh;
  meta = {
    description = "wofi run/emoji/soundboard menus (subset of ~/bin/wofi.zsh)";
    platforms = lib.platforms.linux;
    mainProgram = "wofi-menu";
  };
}
