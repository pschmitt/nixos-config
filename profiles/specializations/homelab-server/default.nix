# homelab-server — shared infra baseline for the fnuc/lrz home server (same
# physical box; lrz is its in-progress NixOS-install replacement for fnuc).
# Only what's genuinely identical between the two host configs lives here;
# host-specific values (network interfaces, VM staging vs. production,
# backup/migration state) stay in hosts/fnuc/ and hosts/lrz/.
{ config, lib, ... }:
{
  imports = [
    ../interactive-server
    ../../features/desktop/linger.nix

    ../../../services/syslog-server.nix
    ../../../services/luks-ssh-unlock/fleet.nix
    ../../../services/smokeping.nix
    ../../../services/reolink-ftp.nix
    ../../../services/watchyourlan.nix
    ../../../services/web-vnc-console.nix
    ../../../services/kvm-usb.nix
    ../../../services/nfs/nfs-server.nix
    ./nix.nix
    ./ssh-clipboard.nix
  ];

  home-manager.users.${config.mainUser.username}.imports = [
    ../../../home-manager/wl-paste-shim.nix
  ];

  services = {
    fwupd.enable = true;
    kvm-usb-passthrough.enable = true;

    nfsExports = {
      enable = true;
      basePath = "/mnt";
      exports = [ "sda1" ];
      allowedIps = [
        "10.5.0.0/22"
        "100.64.0.0/10"
      ];
      exportOptions = "rw,sync,nohide,insecure,no_subtree_check,no_root_squash,anonuid=1000,anongid=1000";
    };
  };

  # Never export the underlying root filesystem if the SATA mount is missing.
  systemd.services.nfs-server = {
    unitConfig.RequiresMountsFor = [ "/mnt/sda1" ];
    bindsTo = [ "mnt-sda1.mount" ];
    after = [ "mnt-sda1.mount" ];
  };

  hardware = {
    biosBoot = false;
    kvmGuest = false;
    cattle = false;
  };

  # Auto-unlock the encrypted data disk using the key installed on the root
  # filesystem by the initrd SSH-unlock preparation.
  boot.initrd.luks.devices.data-encrypted = {
    keyFile = lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
  };
}
