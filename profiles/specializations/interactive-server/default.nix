# interactive-server — server hosts with a personal interactive shell (fnuc, lrz).
{ ... }:
{
  imports = [
    ../server
    ../server/interactive/gpg.nix
    ../server/interactive/syncthing.nix
  ];
}
