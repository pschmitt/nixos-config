{ config, lib }:
let
  termuxMode = config.termux.enable or false;
in
{
  inherit termuxMode;

  pluginPath =
    name: relativePath: nixPath:
    if termuxMode then
      ''"$TERMUX_GENERATION/shell/plugins/${name}/${relativePath}"''
    else
      lib.escapeShellArg (toString nixPath);

  pluginTree =
    name: relativePath: nixPath:
    if termuxMode then
      ''"$TERMUX_GENERATION/shell/plugins/${name}/${relativePath}"''
    else
      toString nixPath;
}
