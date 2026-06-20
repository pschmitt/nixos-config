{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.browser;
in
{
  config = lib.mkMerge [
    {
      custom.browser.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      # NOTE see also home-manager/gui/browser.nix
      programs.firefox.enable = cfg.firefox.enable;

      environment.systemPackages = cfg.systemPackages;
    })
  ];
}

# vim: set ft=nix et ts=2 sw=2 :
