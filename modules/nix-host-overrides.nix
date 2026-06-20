{ lib, ... }:
{
  options.nixHost = {
    extraSubstituters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "https://cache.rofl-10.brkn.lol"
        "https://cache.rofl-13.brkn.lol"
        "https://cache.rofl-14.brkn.lol"
      ];
      description = "Additional substituters appended to the shared Nix substituter list for this host.";
    };
  };
}
