{
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  home.packages = lib.optionals osConfig.services.xserver.enable [
    pkgs.onlyoffice-desktopeditors
    pkgs.thunderbird
  ];

}
