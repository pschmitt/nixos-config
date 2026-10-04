{ lib, ... }:
{
  options.termux = {
    enable = lib.mkEnableOption "Termux-specific Home Manager configuration";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Termux APT packages required by the Home Manager profile.";
    };
  };
}
