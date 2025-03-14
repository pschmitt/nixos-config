{
  disko.devices = {
    disk.nvme0n1 = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            label = "EFI";
            name = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "defaults" ];
            };
          };
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
              # settings = {
              #   keyFile = "/tmp/secret.key";
              #   fallbackToPassword = true;
              # };
              # settings.keyFile = "/tmp/secret.key";
              # additionalKeyFiles = ["/tmp/additionalSecret.key"];
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  # sudo btrfs subvolume create /home/.snapshots
                  # "@home/.snapshots" = {
                  #   mountOptions = [ "compress=zstd" ];
                  # };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
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
