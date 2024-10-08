{ ... }:
{
  # https://search.nixos.org/options?channel=unstable&type=options&query=system.autoUpgrade
  system.autoUpgrade = {
    enable = true;
    flake = "github:pschmitt/nixos-config";
    # flags = [ ];

    dates = "02:30";
    randomizedDelaySec = "7200";
    fixedRandomDelay = true;

    allowReboot = true;
    rebootWindow = {
      lower = "02:00";
      upper = "07:00";
    };
  };
}
