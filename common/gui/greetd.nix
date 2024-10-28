{
  config,
  pkgs,
  ...
}:
let
  hyprland-uwsm = pkgs.writeShellApplication {
    name = "hyprland-uwsm";
    runtimeInputs = [
      pkgs.gawk
      pkgs.util-linux
    ];
    text = ''
      CMD=$(awk -F '=' '/^Exec=/ { print $2; exit }' \
       "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions/hyprland-uwsm.desktop")
      logger -t greetd "Starting session: $CMD"
      eval "$CMD"
    '';
  };
in
{
  # https://nixos.wiki/wiki/Greetd
  services.greetd = {
    enable = true;
    restart = false; # Disabled b/c of autologin

    settings = {
      initial_session = {
        command = "${hyprland-uwsm}/bin/hyprland-uwsm";
        user = config.custom.username;
      };

      # default_session = initial_session;
      default_session = {
        command = ''
          ${pkgs.greetd.tuigreet}/bin/tuigreet \
            --time \
            --remember \
            --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions
        '';
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
