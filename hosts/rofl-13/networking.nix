{ lib, ... }:
{
  networking.hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
}
