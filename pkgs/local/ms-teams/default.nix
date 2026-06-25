# Nix-native replacement for the zhj ms-teams:: helpers (in-a-meeting/url/title).
{
  lib,
  stdenv,
  writeShellApplication,
  inputs,
  jq,
  gnugrep,
  gnused,
  coreutils,
}:
let
  bruvtab = inputs.bruvtab.packages.${stdenv.hostPlatform.system}.default;
in
writeShellApplication {
  name = "ms-teams";
  runtimeInputs = [
    bruvtab
    jq
    gnugrep
    gnused
    coreutils
  ];
  text = builtins.readFile ./ms-teams.sh;
  meta = {
    description = "MS Teams meeting lookup / in-a-meeting check (replaces ms-teams:: zsh helpers)";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
    mainProgram = "ms-teams";
  };
}
