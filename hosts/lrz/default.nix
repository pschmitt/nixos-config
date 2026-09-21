{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../profiles/roles/interactive-server.nix

    # home-manager configuration (TEST!)
    ../../profiles/gui/linger.nix

    # HTTPS and ACME via nginx
    ../../services/http.nix

    # FNUC-007: Native syslog-ng and logrotate service
    ../../services/syslog-server.nix

    # FNUC-008: Native fleet LUKS SSH unlock service
    ../../services/luks-ssh-unlock-fleet.nix

    # FNUC-009: Native SmokePing latency monitor
    ../../services/smokeping.nix

    # FNUC-010: Camera FTP upload and prune timer
    ../../services/reolink-ftp.nix

    # FNUC-012: WatchYourLAN host discovery service
    ../../services/watchyourlan.nix

    # FNUC-020: Emergency noVNC Web Console for Home Assistant VM
    ../../services/web-vnc-console.nix

    # FNUC-006: Native KVM USB passthrough watchdog
    ../../services/kvm-usb.nix

    # FNUC-013: Headless staging browser with CDP and noVNC
    ./browser.nix

    # FNUC-014: Staged Home Manager user services isolation
    ./user-services.nix

    # FNUC-015: Restic backup configuration with migration locking
    ./backups.nix

    # Console rendering (kmscon) for the physical/KVM display
    ./kmscon.nix

    # FNUC-011: Declarative NFS export server
    ./nfs.nix

    # Host networking: hostName, firewall, Wi-Fi fallback
    ./networking.nix

    # FNUC-005: Home Assistant OS VM hosting (libvirtd + bridge)
    ./hass-vm.nix

    # FNUC-018: fnuc -> lrz migration presync + safety guard
    ./fnuc-migration.nix

    ../../profiles/roles/homelab-server.nix
  ];

  services = {
    fwupd.enable = true;
    kvm-usb-passthrough.enable = true;
    watchyourlan.interfaces = [
      "hass-br0"
      "wlp2s0"
    ];
  };

  hardware = {
    biosBoot = false;
    # NOTE avoids setting kernelParams that are only relevant for kvm guests
    # Having this set to true will cause the system to hang on boot and
    # you will *not* be able to enter the luks password on the console
    kvmGuest = false;
  };

  # Auto-unlock encrypted data volume in initrd using key on root filesystem
  boot.initrd.luks.devices.data-encrypted = {
    keyFile = lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
  };
}
