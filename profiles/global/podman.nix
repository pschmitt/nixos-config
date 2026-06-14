{ pkgs, ... }:
{
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    defaultNetwork.settings = {
      dns_enabled = true;
    };
    autoPrune = {
      enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    podman-compose
  ];
}
