{ lib }:
{
  pluginPath =
    _name: _relativePath: nixPath:
    lib.escapeShellArg (toString nixPath);

  pluginTree = _name: _relativePath: toString;
}
