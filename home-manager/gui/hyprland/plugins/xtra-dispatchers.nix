{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  pkg = inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.xtra-dispatchers;
  so = lib.findFirst (p: lib.hasSuffix ".so" (toString p)) (throw "xtra-dispatchers: no .so found") (
    lib.filesystem.listFilesRecursive "${pkg}/lib"
  );
in
{
  xdg.configFile."hypr/lua/plugin-xtra-dispatchers.lua".text = ''
    hl.plugin.load("${so}")
  '';
}
