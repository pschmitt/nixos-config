{ config, ... }:
let
  peerNames = [
    "fnuc"
    "ge2"
    "gk4"
    "lrz"
  ];
  allPeers = map (name: {
    inherit name;
    sshCommand = "ssh -F ${config.home.homeDirectory}/.ssh/config -oProxyCommand=none ${name}";
  }) peerNames;
in
{
  services.ssh-clipboard = {
    enable = true;
    # The upstream default (75 ms) reads the whole Wayland clipboard ~13 times
    # a second, about 15% of a core on gk4; half a second of sync latency is
    # plenty.
    pollIntervalMs = 500;
    peers = builtins.filter (peer: peer.name > config.services.ssh-clipboard.nodeName) allPeers;
  };
}
