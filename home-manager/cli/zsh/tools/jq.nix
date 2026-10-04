{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  colorsJq = pkgs.fetchFromGitHub {
    owner = "pschmitt";
    repo = "colors.jq";
    rev = "c653832ac158dac8c782b7fdbcf675b971efe2bd";
    hash = "sha256-YRS20MNDhGwCLwF3toE475rGVmhe9QSeI7UU1pN756E=";
  };
  plibJq = pkgs.fetchFromGitHub {
    owner = "pschmitt";
    repo = "plib.jq";
    rev = "c02ca973a5ca2d054051c73406f05975fe0a4434";
    hash = "sha256-nu3hmVmTf9M3D0V+4DA9ttBqw9iomySl47Dv+poG23g=";
  };
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.jq ];
  xdg.configFile = {
    "jq/colors".source = colorsJq;
    "jq/plib".source = plibJq;
  };
}
