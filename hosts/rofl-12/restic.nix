{
  services.restic.backups.main = {
    exclude = [
      "/var/lib/***REMOVED***"
    ];
  };
}
