# Shared helpers for installing repo shell scripts into a home-manager profile
# with a sensible runtime PATH. Used by services that exec user scripts
# (go-hass-agent, lnxlink, ...).
#
# This is a plain function library, NOT a home-manager module — import it
# explicitly: `import ./script-lib.nix { inherit lib pkgs; }`.
{ lib, pkgs }:
let
  # Wrap a single script. The whole `dir` is referenced (not just the file) so
  # sibling files (eg. lib.sh) stay next to it in the store and relative
  # `source` statements keep working.
  wrapScript =
    {
      dir,
      name,
      runtimeInputs ? [ ],
      extraPath ? [ ],
    }:
    pkgs.writeShellScript name ''
      export PATH="${lib.makeBinPath runtimeInputs}:${lib.concatStringsSep ":" extraPath}:$PATH"
      exec ${pkgs.bash}/bin/bash ${dir}/${name} "$@"
    '';

  # Wrap every regular file in `dir` (optionally filtered by name) into an
  # attrset { "<name>" = <wrapped-script>; }.
  wrapDir =
    {
      dir,
      runtimeInputs ? [ ],
      extraPath ? [ ],
      filter ? (_: true),
    }:
    let
      regular = lib.filterAttrs (_: type: type == "regular") (builtins.readDir dir);
      selected = lib.filterAttrs (name: _: filter name) regular;
    in
    lib.mapAttrs (
      name: _:
      wrapScript {
        inherit
          dir
          name
          runtimeInputs
          extraPath
          ;
      }
    ) selected;

  # Turn { "<name>" = <script>; } into home-manager file entries under `prefix`,
  # ready for `home.file` / `xdg.configFile`.
  toFiles =
    prefix: scripts:
    lib.mapAttrs' (name: script: {
      name = "${prefix}/${name}";
      value = {
        source = script;
        executable = true;
      };
    }) scripts;
in
{
  inherit wrapScript wrapDir toFiles;
}
