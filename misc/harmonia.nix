{ config, ... }:
{
  sops.secrets."nix/store/privkey" = {
    sopsFile = config.custom.sopsFile;
  };

  services.harmonia = {
    enable = true;
    signKeyPath = config.sops.secrets."nix/store/privkey".path;
    settings = {
      bind = "127.0.0.1:5000";
    };
  };
}
