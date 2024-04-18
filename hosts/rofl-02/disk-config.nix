{ lib, ... }:
{
  disko.devices = {
    disk.disk1 = {
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          # mbr, bios
          boot = {
            name = "boot";
            size = "1M";
            # size = "512M";
            type = "EF02";
            # content = {
            #   type = "filesystem";
            #   format = "ext4";
            #   mountpoint = "/boot";
            # };
          };
          # esp = {
          #   name = "ESP";
          #   size = "512M";
          #   type = "EF00";
          #   content = {
          #     type = "filesystem";
          #     format = "vfat";
          #     mountpoint = "/boot/efi";
          #   };
          # };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "encrypted";
              extraOpenArgs = [ "--allow-discards" ];
              # if you want to use the key for interactive login be sure there
              # is no trailing newline.
              # for example use `echo -n "password" > /tmp/secret.key`
              # keyFile = "/tmp/secret.key"; # Interactive
              settings = {
                keyFile = "/tmp/disk-1.key";
                fallbackToPassword = true;
              };
              # settings.keyFile = "/tmp/secret.key";
              # additionalKeyFiles = ["/tmp/additionalSecret.key"];
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
