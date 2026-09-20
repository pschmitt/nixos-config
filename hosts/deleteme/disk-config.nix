_:
let
  tfVars = builtins.fromJSON (builtins.readFile ./tf-vars.json);
in
{
  disko.devices.disk.system = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_${tfVars.disks.root.id}";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
