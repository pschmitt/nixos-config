{ hostname, inputs, ... }:
let
  privateConfig = inputs.nixos-config-private.outPath;
  hostSecrets = privateConfig + "/hosts/${hostname}";
in
{
  termux = {
    cache.credentialsSopsFile = privateConfig + "/secrets/${hostname}-termux-cache.sops.yaml";
    sshd.ports = [ 2222 ];
    ssh = {
      hostKeysSopsFile = hostSecrets + "/${hostname}-termux-host-keys.sops.yaml";
      knownHostsSopsFile = hostSecrets + "/${hostname}-termux-known-hosts.sops.yaml";
    };
  };
}
