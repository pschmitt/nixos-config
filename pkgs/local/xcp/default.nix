# Nix port of the yadm ~/bin/xcp clipboard helper. No runtimeInputs on
# purpose: it picks its backend (wl-copy, xclip, xsel, OSC 52, clipper,
# lemonade, termux) by probing what the caller's PATH offers.
{
  lib,
  writeShellApplication,
}:
writeShellApplication {
  name = "xcp";
  runtimeInputs = [ ];
  # The script probes optional tools and unset session variables.
  bashOptions = [ ];
  # Kept identical to the yadm copy, which has one unused variable.
  excludeShellChecks = [ "SC2034" ];
  text = builtins.readFile ./xcp.sh;
  meta = {
    description = "Copy to whichever clipboard the current session offers";
    platforms = lib.platforms.unix;
    mainProgram = "xcp";
  };
}
