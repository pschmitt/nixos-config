{
  config,
  inputs,
  lib,
  ...
}:
let
  knownHosts = import ../../profiles/base/ssh-known-hosts.nix {
    inherit inputs;
    inherit (config) domains;
  };
in
{
  imports = [ ../domains.nix ];

  environment.etc."ssh/ssh_known_hosts".text = lib.concatLines (
    map (host: "${lib.concatStringsSep "," host.hostNames} ${host.publicKey}") (
      builtins.attrValues knownHosts
    )
  );
}
