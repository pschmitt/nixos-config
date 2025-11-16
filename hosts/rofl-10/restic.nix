{
  services.restic.backups.main = {
    paths = [ "/mnt/data/srv" ];
    exclude = [ "/mnt/data/srv/***REMOVED***d/data" ];
  };
}
