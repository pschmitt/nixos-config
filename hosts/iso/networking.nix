{ lib, ... }:
{
  networking = {
    useDHCP = lib.mkForce true;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };
}
