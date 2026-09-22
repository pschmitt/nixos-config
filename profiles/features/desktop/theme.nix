{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.desktop.theme;
in
{
  config = lib.mkMerge [
    {
      dotfiles.desktop.theme.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      environment.systemPackages = cfg.systemPackages;
    })
  ];
}
