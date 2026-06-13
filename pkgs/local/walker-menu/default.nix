# walker-menu — soundboard/misc/meetings menus using walker dmenu.
# run and emoji are now called directly via walker / walker -m emojis.
{
  lib,
  writeShellApplication,
  walker,
  emoji-fzf,
  soundboard,
  libnotify,
  wl-clipboard,
  curl,
  jq,
  coreutils,
  psmisc,
}:
writeShellApplication {
  name = "walker-menu";
  runtimeInputs = [
    walker
    emoji-fzf
    soundboard
    libnotify
    wl-clipboard
    curl
    jq
    coreutils
    psmisc
  ];
  text = builtins.readFile ./walker-menu.sh;
  meta = {
    description = "walker dmenu soundboard/misc/meetings menus";
    platforms = lib.platforms.linux;
    mainProgram = "walker-menu";
  };
}
