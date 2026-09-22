{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.desktop.theme;
in
{
  config = lib.mkMerge [
    {
      custom.desktop.theme.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      environment.systemPackages = cfg.systemPackages;
    })
  ];
}
