{ config, ... }:
{
  services.xserver.displayManager.gdm = {
    enable = true;
    debug = true;
    settings = { };
    autoLogin.delay = 0;
  };

  services.displayManager = {
    autoLogin = {
      enable = true;
      user = config.custom.username;
    };

    # FIXME This doesn't work. Gnome gets started instead of hyprland
    # https://github.com/NixOS/nixpkgs/issues/334404
    defaultSession = "hyprland-uwsm";
  };
}
