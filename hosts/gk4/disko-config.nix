{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WD_PC_SN740_SDDPNQE-2T00_251517802927";
    content = {
      type = "gpt";
      partitions = {
        mbr = {
          label = "MBR"; # FIXME, this has no effect?
          size = "1M";
          type = "EF02"; # for grub MBR
          priority = 1;
        };
        ESP = {
          name = "ESP";
          label = "EFI";
          size = "10G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "defaults" ];
            extraArgs = [
              "-n"
              "EFI"
            ];
          };
        };
        luks = {
          size = "100%";
          # label = "luks-root";
          content = {
            type = "luks";
            name = "luks-root";
            extraOpenArgs = [ "--allow-discards" ];
            # if you want to use the key for interactive login be sure there is no trailing newline
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
              extraArgs = [
                "-L"
                "luks-root"
              ];
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
                # FIXME Snapper
                # "/home/.snapshots" = { };
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
}
