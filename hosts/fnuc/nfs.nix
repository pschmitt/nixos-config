{
  imports = [ ../../services/nfs/nfs-server.nix ];

  services.nfsExports = {
    enable = true;
    basePath = "/mnt";
    exports = [ "sda1" ];
    allowedIps = [
      "10.5.0.0/22"
      "100.64.0.0/10"
    ];
    exportOptions = "rw,sync,nohide,insecure,no_subtree_check,no_root_squash,anonuid=1000,anongid=1000";
  };

  # Never export the underlying root filesystem if the SATA mount is missing.
  systemd.services.nfs-server = {
    unitConfig.RequiresMountsFor = [ "/mnt/sda1" ];
    bindsTo = [ "mnt-sda1.mount" ];
    after = [ "mnt-sda1.mount" ];
  };
}
