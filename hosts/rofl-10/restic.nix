{
  services.restic.backups.main = {
    paths = [
      "/mnt/data/srv"
      "/mnt/data/blobs"
    ];
    exclude = [
      "/mnt/data/srv/monerod/data"

      # ignore nix isos/sd-card images
      "/mnt/data/blobs/img"
      "/mnt/data/blobs/iso"
    ];
  };
}
