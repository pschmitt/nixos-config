{ lib, ... }:
{
  networking.useNetworkd = lib.mkDefault true;

  # Prefer Cloudflare DNS on servers (also used by some container modules that
  # read `config.networking.nameservers` to populate container resolv.conf).
  networking.nameservers = lib.mkDefault [
    "1.1.1.1"
    "1.0.0.1"
  ];

  # Make systemd-resolved use Cloudflare as its primary resolvers (not only as
  # fallback).
  services.resolved.settings.Resolve.DNS = [
    "1.1.1.1#one.one.one.one"
    "1.0.0.1#one.one.one.one"
  ];
}
