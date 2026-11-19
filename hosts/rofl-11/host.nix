{ lib, ... }:
{
  dotfiles.promptColor = "#9C62C5";
  networking.hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);

  # Unlike the other OpenStack servers (enp3s0), this host's NIC is ens3.
  networking.nat.externalInterface = "ens3";
}
