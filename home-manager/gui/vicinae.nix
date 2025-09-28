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
      theme.name = "vicinae-dark";
      window = {
        csd = true;
        opacity = 1;
        rounding = 10;
      };
    };
  };
}
