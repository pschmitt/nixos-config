{ inputs, ... }:
let
  vicinaeModule = inputs.vicinae.homeManagerModules.default;
in
{
  imports = [ vicinaeModule ];

  services.vicinae = {
    enable = true;
  };
}
