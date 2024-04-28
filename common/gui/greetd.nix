{ lib, config, pkgs, hyprlandPkg, hyprland-wrapper, ... }: {
  # https://nixos.wiki/wiki/Greetd
  services.greetd = {
    enable = true;
    restart = false; # Disabled b/c of autologin
    settings = {
      initial_session = {
        # command = "${hyprlandPkg}/bin/Hyprland";
        command = "${hyprland-wrapper}/bin/hyprland-wrapper";
        user = config.custom.username;
      };
      # default_session = initial_session;
      default_session = {
        command = lib.concatStringsSep " " [
          "${pkgs.greetd.tuigreet}/bin/tuigreet"
          "--time"
          "--remember"
          "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions:${config.services.displayManager.sessionData.desktops}/share/xsessions"
          "--cmd ${hyprland-wrapper}/bin/hyprland-wrapper"
        ];
        user = "greeter";
      };
    };
  };

  # https://github.com/sjcobb2022/nixos-config/blob/main/hosts%2Fcommon%2Foptional%2Fgreetd.nix#L25-L26
  systemd.services.greetd.serviceConfig = {
    Type = "idle";
    StandardInput = "tty";
    StandardOutput = "tty";
    StandardError = "journal"; # Without this errors will spam on screen
    # Without these bootlogs will spam on screen
    TTYReset = true;
    TTYVHangup = true;
    TTYVTDisallocate = true;
  };

  # unlock gnome keyring automatically with greetd
  security.pam.services.greetd.enableGnomeKeyring = true;
}
