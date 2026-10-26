{ config, lib, ... }:
{
  options.nixHost = {
    cacheHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # Fleet hosts that serve their store through Harmonia
      # (services/harmonia.nix), at cache.<host>.<main domain>.
      default = [
        "rofl-10"
        "rofl-13"
        "rofl-14"
        "rofl-15"
        "rofl-16"
      ];
      description = "Fleet hosts serving an authenticated Harmonia cache.";
    };

    extraSubstituters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional substituters appended to the shared Nix substituter list for this host.";
    };
  };

  # A regular definition, so hosts and profiles add substituters to the fleet
  # caches instead of replacing them. A host does not substitute from itself.
  config.nixHost.extraSubstituters = map (host: "https://cache.${host}.${config.domains.main}") (
    lib.remove config.networking.hostName config.nixHost.cacheHosts
  );
}
