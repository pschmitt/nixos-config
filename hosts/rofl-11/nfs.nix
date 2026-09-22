{
  imports = [ ../../services/nfs/nfs-server.nix ];

  services.nfsExports = {
    enable = true;
    allowedIps = [ "100.64.0.0/10" ];
    exports = [
      "audiobooks"
      "books"
      "srv"
      "videos"
    ];
  };
}
