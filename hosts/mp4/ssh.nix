{ hostname, inputs, ... }:
{
  termux.ssh.hostKeysSopsFile =
    inputs.nixos-config-private.outPath + "/hosts/${hostname}/${hostname}-termux-host-keys.sops.yaml";
}
