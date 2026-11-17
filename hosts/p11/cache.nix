{ inputs, ... }:
{
  termux.cache.credentialsSopsFile =
    inputs.nixos-config-private.outPath + "/secrets/p11-termux-cache.sops.yaml";
}
