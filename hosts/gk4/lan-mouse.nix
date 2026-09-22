{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.services.lan-mouse = {
    enable = true;
    autoStart = false;
    peers = [
      {
        name = "ge2";
        position = "left";
      }
    ];
  };
}
