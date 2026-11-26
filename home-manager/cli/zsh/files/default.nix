{ lib, ... }:
let
  filesIn =
    directory: destination:
    lib.concatLists (
      lib.mapAttrsToList (
        name: kind:
        let
          source = directory + "/${name}";
          target = "${destination}/${name}";
        in
        if kind == "directory" then
          filesIn source target
        else if kind == "regular" || kind == "symlink" then
          [
            {
              name = target;
              value.source = source;
            }
          ]
        else
          [ ]
      ) (builtins.readDir directory)
    );
  functions =
    directory:
    lib.concatLists (
      lib.mapAttrsToList (
        name: kind:
        let
          source = directory + "/${name}";
          target = "zsh/functions/${name}";
        in
        if kind != "directory" then
          [ ]
        else if
          builtins.elem name [
            "pulseaudio"
            "strings"
          ]
        then
          filesIn source target
        else
          [
            {
              name = target;
              value = {
                inherit source;
                recursive = true;
              };
            }
          ]
      ) (builtins.readDir directory)
    );
in
{
  xdg.configFile =
    builtins.listToAttrs (functions ./functions ++ filesIn ./plugins/local "zsh/plugins/local")
    // {
      "zsh/static/README.md".source = ./static/README.md;
    };
}
