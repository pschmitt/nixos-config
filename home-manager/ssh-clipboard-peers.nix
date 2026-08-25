{ config, ... }:
let
  peerNames = [
    "fnuc"
    "ge2"
    "gk4"
  ];
  allPeers = map (name: {
    inherit name;
    sshCommand = "ssh -F ${config.home.homeDirectory}/.ssh/config -oProxyCommand=none ${name}";
  }) peerNames;
in
{
  services.ssh-clipboard = {
    enable = true;
    peers = builtins.filter (peer: peer.name > config.services.ssh-clipboard.nodeName) allPeers;
  };
}
