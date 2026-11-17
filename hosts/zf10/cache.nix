{ inputs, ... }:
{
  termux.cache.credentialsSopsFile =
    inputs.nixos-config-private.outPath + "/secrets/zf10-termux-cache.sops.yaml";
}
