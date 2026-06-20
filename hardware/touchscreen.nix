{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkMerge [
    {
      hardware = {
        touchscreen.enable = true;
        sensor.iio.enable = lib.mkDefault true;
      };
    }
    (lib.mkIf config.hardware.touchscreen.enable {
      environment.systemPackages = with pkgs; [
        # virtual keyboard for touchscreens
        wvkbd
        squeekboard
      ];
    })
  ];
}
