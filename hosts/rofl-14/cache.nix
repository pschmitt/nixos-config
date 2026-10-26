{
  imports = [ ../../services/harmonia-cache.nix ];
  services.harmonia.publication = {
    enable = true;
    populate = true;
    replicaHost = "rofl-13";
  };
}
