# Nix port of the yadm ~/bin/pinentry-guess.sh: gpg-agent's pinentry-program
# (yadm gpg-agent.conf). Picks pinentry-gnome3/-qt in a desktop session and
# pinentry-curses otherwise, from the caller's PATH (no runtimeInputs).
{
  lib,
  writeShellApplication,
}:
writeShellApplication {
  name = "pinentry-guess";
  runtimeInputs = [ ];
  # Probes optional pinentry flavors and unset session variables.
  bashOptions = [ ];
  text = builtins.readFile ./pinentry-guess.sh;
  meta = {
    description = "Pick a pinentry flavor for the current session";
    platforms = lib.platforms.linux;
    mainProgram = "pinentry-guess";
  };
}
