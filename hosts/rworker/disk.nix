# Encrypted scratch disk. The image holds only the ESP (systemd-boot, the
# kernel and an initrd with the whole system as squashfs). On every boot
# the initrd generates a random key, (re)creates the data partition as LUKS2
# with it and mounts it as the writable store layer. The key only ever
# exists in RAM, so a reboot leaves an unreadable partition behind, which
# the next boot wipes and creates again.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  keyDir = "/run/rworker";
  keyFile = "${keyDir}/luks.key";
  mapperName = "workerdata";
in
{
  # The OpenStack image is booted with hw_disk_bus=virtio.
  boot.initrd = {
    # Without a luks.devices entry nixpkgs adds no crypto modules itself.
    availableKernelModules = [
      "virtio_blk"
      "virtio_pci"
      "dm_crypt"
    ]
    ++ config.boot.initrd.luks.cryptoModules;

    systemd = {
      # systemd-repart formats the data partition itself; the open service
      # below needs systemd-cryptsetup (no crypttab entry pulls it in).
      extraBin = {
        head = "${pkgs.coreutils}/bin/head";
        "mkfs.ext4" = "${pkgs.e2fsprogs}/bin/mkfs.ext4";
        systemd-cryptsetup = "${config.boot.initrd.systemd.package}/bin/systemd-cryptsetup";
      };

      repart = {
        enable = true;
        device = "/dev/vda";
        extraArgs = [
          "--key-file=${keyFile}"
          # Drop the previous boot's data partition (its key is gone).
          "--factory-reset=yes"
        ];
      };

      services = {
        rworker-luks-key = {
          description = "Generate this boot's key for the worker data partition";
          unitConfig.DefaultDependencies = false;
          before = [ "systemd-repart.service" ];
          requiredBy = [ "systemd-repart.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
          };
          script = ''
            mkdir -p ${keyDir}
            head -c 64 /dev/urandom > ${keyFile}
          '';
        };

        # Open the partition repart just created. Not a crypttab entry: its
        # generated unit binds to the by-partlabel device, which on every
        # boot after the first already exists (the old partition) and
        # vanishes when repart replaces it, failing the unit.
        rworker-open-data = {
          description = "Open this boot's encrypted worker data partition";
          unitConfig.DefaultDependencies = false;
          # Ordering only: repart is stopped before switch-root, and a
          # Requires= would stop this unit too. Stopping it does not close
          # the volume (there is no ExecStop), so the store stays mounted.
          after = [
            "systemd-repart.service"
            "systemd-udevd.service"
          ];
          wants = [ "systemd-repart.service" ];
          # Nothing pulls in cryptsetup.target without crypttab entries.
          before = [ "initrd-fs.target" ];
          wantedBy = [ "initrd.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            udevadm settle
            systemd-cryptsetup attach \
              ${mapperName} /dev/disk/by-partlabel/worker-data ${keyFile} luks
          '';
        };
      };
    };
  };

  # The writable store layer (and the build directory below) live on the
  # encrypted partition instead of netboot's tmpfs.
  fileSystems."/nix/.rw-store" = lib.mkForce {
    device = "/dev/mapper/${mapperName}";
    fsType = "ext4";
    neededForBoot = true;
  };

  nix.settings.build-dir = "/nix/.rw-store/builds";

  systemd = {
    repart.partitions."10-worker-data" = {
      Type = "linux-generic";
      Label = "worker-data";
      Format = "ext4";
      Encrypt = "key-file";
      FactoryReset = "yes";
    };

    tmpfiles.rules = [ "d /nix/.rw-store/builds 0755 root root -" ];

    # The key is no longer needed once the partition is open.
    services.rworker-forget-luks-key = {
      description = "Remove the worker data partition key from /run";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [ "/nix/.rw-store" ];
      serviceConfig.Type = "oneshot";
      script = "rm -f ${keyFile}";
    };
  };
}
