# Device groups for scoping which Syncthing folders each device is invited
# to. px5 and p11 are intentionally left out of every group here -- they're
# still paired devices (profiles/syncthing-devices.json) but only feed the
# separate Gadgetbridge folder (services/endurain.nix), never the personal
# Documents/Music/Pictures/Backups folders.
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
}
