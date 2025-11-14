{ pkgs, ... }:
{

  hardware.sensor.iio.enable = true;

  environment.systemPackages = with pkgs; [
    # virtual keyboard for touchscreens
    wvkbd
    squeekboard
  ];
}
