{ lib, ... }:
{
  custom.promptColor = "#9C62C5";
  networking.hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
}
