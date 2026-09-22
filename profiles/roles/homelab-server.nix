# homelab-server — shared infra baseline for the fnuc/lrz home server (same
# physical box; lrz is its in-progress NixOS-install replacement for fnuc).
# Only what's genuinely identical between the two host configs lives here;
# host-specific values (network interfaces, VM staging vs. production,
# backup/migration state) stay in hosts/fnuc/ and hosts/lrz/.
{ config, lib, ... }:
{
  imports = [
    ../gui/linger.nix

    ../../services/syslog-server.nix
    ../../services/luks-ssh-unlock-fleet.nix
    ../../services/smokeping.nix
    ../../services/reolink-ftp.nix
    ../../services/watchyourlan.nix
    ../../services/web-vnc-console.nix
    ../../services/kvm-usb.nix
  ];

  home-manager.users.${config.mainUser.username}.imports = [
    ../../home-manager/wl-paste-shim.nix
  ];

  services = {
    fwupd.enable = true;
    kvm-usb-passthrough.enable = true;
  };

  hardware = {
    biosBoot = false;
    kvmGuest = false;
  };

  # Auto-unlock the encrypted data disk using the key installed on the root
  # filesystem by the initrd SSH-unlock preparation.
  boot.initrd.luks.devices.data-encrypted = {
    keyFile = lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
  };
}
