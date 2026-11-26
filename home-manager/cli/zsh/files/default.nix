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
in
{
  xdg.configFile = builtins.listToAttrs (
    filesIn ./functions "zsh/functions" ++ filesIn ./plugins/local "zsh/plugins/local"
  );
}
