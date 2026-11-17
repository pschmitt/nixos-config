{ hostname, inputs, ... }:
{
  termux = {
    sshd.ports = [ 2222 ];
    ssh.hostKeysSopsFile =
      inputs.nixos-config-private.outPath + "/hosts/${hostname}/${hostname}-termux-host-keys.sops.yaml";
    ssh.knownHostsSopsFile =
      inputs.nixos-config-private.outPath + "/hosts/${hostname}/${hostname}-termux-known-hosts.sops.yaml";
  };
}
