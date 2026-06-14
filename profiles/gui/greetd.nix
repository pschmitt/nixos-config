{
  config,
  pkgs,
  ...
}:
let
  # Single script that dynamically extracts and runs the Exec= line
  # from the matching "*-uwsm.desktop" file, given a compositor name.
  uwsm-run-bin = pkgs.writeShellApplication {
    name = "uwsm-run";
    runtimeInputs = [
      pkgs.gawk
      pkgs.util-linux
    ];
    text = ''
      log() {
        logger -t greetd "$*"
      }

      # Default to the script name if no compositor is provided
      COMPOSITOR="''${1:-$(basename "$0")}"
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

  uwsm-run = pkgs.stdenv.mkDerivation {
    name = "uwsm-runner-pkg";
    buildCommand = ''
      mkdir -p $out/bin

      # Install main runner script
      cp ${uwsm-run-bin}/bin/uwsm-run $out/bin/uwsm-run

      # Create symlinks
      for compositor in sway hyprland
      do
        ln -s uwsm-run $out/bin/$compositor
      done
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
        command = "${uwsm-run}/bin/hyprland";
        user = config.mainUser.username;
      };

      default_session = {
        command = ''
          ${pkgs.greetd.tuigreet}/bin/tuigreet \
            --time \
            --asterisks \
            --remember \
            --remember-user-session \
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
