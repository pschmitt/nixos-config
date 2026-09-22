{ lib, ... }:
{
  dotfiles.promptColor = "#0B87CA";
  networking.hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
}
