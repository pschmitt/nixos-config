{ ... }: {
  fileSystems."/export/backups" = {
    device = "/mnt/data/backups";
    options = [ "bind" ];
  };
  fileSystems."/export/books" = {
    device = "/mnt/data/books";
    options = [ "bind" ];
  };
  fileSystems."/export/documents" = {
    device = "/mnt/data/documents";
    options = [ "bind" ];
  };
  fileSystems."/export/mnt" = {
    device = "/mnt/data/mnt";
    options = [ "bind" ];
  };
  fileSystems."/export/srv" = {
    device = "/mnt/data/srv";
    options = [ "bind" ];
  };
  fileSystems."/export/tmp" = {
    device = "/mnt/data/tmp";
    options = [ "bind" ];
  };
  fileSystems."/export/videos" = {
    device = "/mnt/data/videos";
    options = [ "bind" ];
  };

  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    /export           100.64.0.0/10(rw,fsid=0,no_subtree_check)
    /export/backups   100.64.0.0/10(rw,nohide,insecure,no_subtree_check)
    /export/books     100.64.0.0/10(rw,nohide,insecure,no_subtree_check)
    /export/documents 100.64.0.0/10(rw,nohide,insecure,no_subtree_check)
    /export/mnt       100.64.0.0/10(rw,nohide,insecure,no_subtree_check)
    /export/srv       100.64.0.0/10(rw,nohide,insecure,no_subtree_check)
    /export/tmp       100.64.0.0/10(rw,nohide,insecure,no_subtree_check)
    /export/videos    100.64.0.0/10(rw,nohide,insecure,no_subtree_check)
  '';
}
