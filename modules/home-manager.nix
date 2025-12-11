{ lib, ... }:
{
  options = {
    home-manager.enabled = lib.mkEnableOption "home-manager for this host";
  };
}
