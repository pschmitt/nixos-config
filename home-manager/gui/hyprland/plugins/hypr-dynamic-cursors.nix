{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  pkg = inputs.hypr-dynamic-cursors.packages.${pkgs.stdenv.hostPlatform.system}.hypr-dynamic-cursors;
  so = lib.findFirst (
    p: lib.hasSuffix ".so" (toString p)
  ) (throw "hypr-dynamic-cursors: no .so found") (lib.filesystem.listFilesRecursive "${pkg}/lib");
in
{
  xdg.configFile."hypr/lua/plugin-dynamic-cursors.lua".text = ''
    hl.plugin.load("${so}")

    hl.config({
        plugin = {
            ["dynamic-cursors"] = {
                enabled = true,
                mode    = "rotate",
            },
        },
    })
  '';
}
