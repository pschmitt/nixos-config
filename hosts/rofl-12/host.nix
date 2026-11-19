{ lib, ... }:
{
  dotfiles.promptColor = "#ff6600";
  networking.hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
}
