{ inputs, ... }:
let
  vicinaeModule = inputs.vicinae.homeManagerModules.default;
in
{
  imports = [ vicinaeModule ];

  services.vicinae = {
    enable = true;
    settings = {
      faviconService = "twenty"; # "twenty" | "google" | "none"
      font = {
        normal = "Comic Code";
        size = 16;
      };
      theme.name = "one-dark";
      window = {
        csd = true;
        opacity = 1;
        rounding = 10;
      };
    };
  };

  systemd.user.services.vicinae.Service.Environment = [
    "QT_SCALE_FACTOR=1.25" # tweak: 1.0 = default, 1.25 = 25% bigger, etc.
    # "USE_LAYER_SHELL=0" # disable layer shell
  ];
}
