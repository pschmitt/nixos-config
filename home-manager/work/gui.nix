{
  lib,
  pkgs,
  guiEnable ? false,
  ...
}:
{
  home.packages = lib.optionals guiEnable [
    pkgs.onlyoffice-desktopeditors
    pkgs.thunderbird
  ];

}
