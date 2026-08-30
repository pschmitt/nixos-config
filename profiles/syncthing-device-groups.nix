# Device groups for scoping which Syncthing folders each device is invited
# to. px5 and p11 are also paired devices (profiles/syncthing-devices.json)
# and feed the separate Gadgetbridge folder (services/endurain.nix), but are
# only meant to get the Documents folder among the personal ones -- never
# Music/Pictures/Backups.
{
  servers = [
    "rofl-10"
    "fnuc"
  ];
  laptops = [
    "ge2"
    "gk4"
    "x13"
  ];
  phones = [ ];
  documentsPhones = [
    "px5"
    "p11"
  ];
}
