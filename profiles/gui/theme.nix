{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.custom.theme;
in
{
  imports = [ inputs.catppuccin.nixosModules.catppuccin ];

  config = lib.mkMerge [
    {
      custom.theme.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      catppuccin = {
        enable = true;
        autoEnable = true;
        inherit (cfg) flavor;
      };

      environment.systemPackages = cfg.systemPackages;
    })
  ];
}
