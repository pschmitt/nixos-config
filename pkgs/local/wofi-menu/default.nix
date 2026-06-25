# Nix-native port of the ~/bin/wofi.zsh launcher (run/emoji/soundboard/misc/meetings).
{
  lib,
  writeShellApplication,
  wofi,
  emoji-fzf,
  soundboard,
  libnotify, # notify-send
  wl-clipboard, # wl-copy
  glib, # gsettings
  curl, # calendar agenda (jcal)
  jq,
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
    curl
    jq
    gawk
    gnused
    gnugrep
    coreutils
    psmisc
  ];
  text = builtins.readFile ./wofi-menu.sh;
  meta = {
    description = "wofi run/emoji/soundboard/misc/meetings menus (replaces ~/bin/wofi.zsh)";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
    mainProgram = "wofi-menu";
  };
}
