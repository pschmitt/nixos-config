# Substitute from fnuc's Harmonia first: it is on the LAN and mirrors these
# hosts' current main systems (hosts/fnuc/nix-cache-mirror.nix), so it beats
# the S3 cache (priority 30) and cache.nixos.org (40).
{ config, ... }:
{
  nix.settings.trusted-public-keys = [ "fnuc:X/5wlLoWwSvNyAm369jFXOgwx7og2VLIs/bzTsoZ85Q=" ];

  nixHost.extraSubstituters = [ "https://cache.fnuc.${config.domains.vpn}?priority=20" ];
}
