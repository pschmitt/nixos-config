{ config, ... }:
{
  services.harmonia.extraVirtualHosts = [
    { domain = "cache.${config.domains.main}"; }
    { domain = "nix-cache.${config.domains.main}"; }
  ];
}
