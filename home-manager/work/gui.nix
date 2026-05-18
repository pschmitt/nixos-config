{
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  hasXserver =
    osConfig != null
    && osConfig ? services
    && osConfig.services ? xserver
    && osConfig.services.xserver.enable;
in
{
  home.packages = lib.optionals hasXserver [
    pkgs.onlyoffice-desktopeditors
    pkgs.thunderbird
  ];

}
