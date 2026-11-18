{
  inputs,
  pkgs,
  modules ? [ ],
  specialArgs ? { },
}:
let
  evaluated = pkgs.lib.evalModules {
    class = "termuxppSystem";
    specialArgs = specialArgs // {
      inherit inputs pkgs;
    };
    modules = [ ./. ] ++ modules;
  };
  failed = builtins.filter (item: !item.assertion) evaluated.config.assertions;
in
assert pkgs.lib.assertMsg (failed == [ ]) (
  pkgs.lib.concatMapStringsSep "\n" (item: item.message) failed
);
{
  inherit (evaluated) config options;
  inherit pkgs;
  system = evaluated.config.system.build.toplevel;
}
