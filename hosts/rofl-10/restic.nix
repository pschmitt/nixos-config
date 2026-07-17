{
  services.restic.backups.main = {
    paths = [
      "/mnt/data/srv"
      "/mnt/data/blobs"
    ];
    exclude = [
      # ignore nix isos/sd-card images
      "/mnt/data/blobs/img"
      "/mnt/data/blobs/iso"
    ];
  };
}
