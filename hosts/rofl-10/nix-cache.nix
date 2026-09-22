{ config, ... }:
{
  nixHost.extraSubstituters = [
    "https://cache.rofl-13.brkn.lol"
    "https://cache.rofl-14.brkn.lol"
  ];

  services.harmonia.extraVirtualHosts = [
    { domain = "cache.${config.domains.main}"; }
    { domain = "nix-cache.${config.domains.main}"; }
  ];
}
