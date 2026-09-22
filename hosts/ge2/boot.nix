{ lib, ... }:
{
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 1;
}
