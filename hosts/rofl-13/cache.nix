{
  imports = [ ../../services/harmonia-cache.nix ];
  services.harmonia.publication.enable = true;

  nixHost.extraSubstituters = [
    "https://cache.rofl-10.brkn.lol"
    "https://cache.rofl-14.brkn.lol"
  ];
}
