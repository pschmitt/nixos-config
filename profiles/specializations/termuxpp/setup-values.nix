# The private values every TermuxPP guest shares for reaching the rworker
# controller and the signed cache: the bootstrap's `nixpp setup` config
# (setup-config.nix) and the guests' /etc/nixpp/upgrade.json `lease` section
# (systems.nix) are both rendered from them. They come from
# nixos-config-private (lib.termuxppSetup), the controller's host key from its
# data/ssh-hosts.generated.json and the cache keys from cache-public-keys.nix.
{ lib, inputs }:
let
  inherit (lib) assertMsg concatStringsSep hasInfix;
  private = inputs.nixos-config-private;
  values = private.lib.termuxppSetup;
  hostKeys = builtins.fromJSON (builtins.readFile "${private.outPath}/data/ssh-hosts.generated.json");
  # Type and key only: the generated data keeps the key's comment.
  controllerHostKey = concatStringsSep " " (
    lib.take 2 (lib.splitString " " (lib.trim hostKeys.${values.controllerHost}.ed25519))
  );
in
assert assertMsg (lib.hasPrefix "ssh-ed25519 " controllerHostKey)
  "nixpp setup config: no ed25519 host key for ${values.controllerHost}";
assert assertMsg (lib.hasPrefix "s3://" values.cache.store)
  "nixpp setup config: cache.store must be an s3:// store";
assert assertMsg (hasInfix "{host}" values.cache.pinUrl)
  "nixpp setup config: cache.pinUrl must contain {host}";
{
  inherit values controllerHostKey;
  cachePublicKeys = import ./cache-public-keys.nix;
}
