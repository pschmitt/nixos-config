{ lib, ... }:
{
  dotfiles.promptColor = "#ff6600";
  networking.hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);

  # The openstack-wiit profile assumes "ens3", but this host's uplink is
  # enp3s0. Without a matching NAT rule, traffic routed through NetBird (WIIT
  # public ranges) leaves with its 100.122.x source address and gets no reply.
  networking.nat.externalInterface = lib.mkForce "enp3s0";
}
