{
  imports = [ ../../services/harmonia-cache.nix ];
  services.harmonia.publication = {
    enable = true;
    populate = true;
    replicaHost = "rofl-13";
  };

  nixHost.extraSubstituters = [
    "https://cache.rofl-10.brkn.lol"
    "https://cache.rofl-13.brkn.lol"
  ];
}
