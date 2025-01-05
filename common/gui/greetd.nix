{
  config,
  pkgs,
  ...
}:
let
  # Single script that dynamically extracts and runs the Exec= line
  # from the matching “-uwsm.desktop” file, given a compositor name.
  uwsm-run = pkgs.writeShellApplication {
    name = "uwsm-run";
    runtimeInputs = [
      pkgs.gawk
      pkgs.util-linux
    ];
    text = ''
      log() {
        logger -t greetd "$*"
      }

      COMPOSITOR="''${1:-hyprland}"
      DESKTOP_FILE="${config.services.displayManager.sessionData.desktops}/share/wayland-sessions/''${COMPOSITOR}-uwsm.desktop"

      if [[ ! -f "$DESKTOP_FILE" ]]
      then
        log "Desktop file not found: $DESKTOP_FILE"
        exit 1
      fi

      # extract cmd from desktop file
      CMD=$(awk -F '=' '/^Exec=/ { print $2; exit }' "$DESKTOP_FILE")

      # FIXME This won't work as CMD is the entire line!
      # example: uwsm-xxx ARGS ACTUAL_COMMAND
      # if [[ ! -x "$CMD" ]]
      # then
      #   logger -t greetd "$CMD is not executable"
      #   exit 1
      # fi

      log "Starting uwsm desktop session using command: $CMD"
      log "UWSM Desktop file: $DESKTOP_FILE"
      exec $CMD
    '';

  };

  hyprland-uwsm = pkgs.writeShellApplication {
    name = "hyprland-uwsm";
    runtimeInputs = [ ];
    text = ''
      exec ${uwsm-run}/bin/uwsm-run hyprland
    '';
  };

  sway-uwsm = pkgs.writeShellApplication {
    name = "sway-uwsm";
    runtimeInputs = [ ];
    text = ''
      exec ${uwsm-run}/bin/uwsm-run sway
    '';
  };
in
{
  # https://nixos.wiki/wiki/Greetd
  services.greetd = {
    enable = true;
    restart = false; # Disabled b/c of autologin (initial session)

    settings = {
      initial_session = {
        command = "${hyprland-uwsm}/bin/hyprland-uwsm";
        # command = "${sway-uwsm}/bin/sway-uwsm";
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
