{ lib, ... }:
{
  hardware = {
    cattle = false;
    serverType = "openstack";
    biosBoot = lib.mkForce false;
  };
}
