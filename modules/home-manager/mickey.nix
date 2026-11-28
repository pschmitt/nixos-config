{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mickey;
  toml = pkgs.formats.toml { };
  python = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
  configFile = "${config.xdg.configHome}/mickey/config.toml";
  managedSettings = toml.generate "mickey-managed.toml" (
    cfg.settings
    // lib.optionalAttrs (cfg.peers != { }) {
      peer = lib.mapAttrsToList (
        name: peer:
        {
          inherit name;
          inherit (peer) address;
        }
        // lib.optionalAttrs (peer.position != null) { inherit (peer) position; }
      ) cfg.peers;
    }
  );
in
{
  options.programs.mickey = {
    enable = lib.mkEnableOption "Mickey keyboard and mouse sharing";
    package = lib.mkPackageOption pkgs "mickey" { };
    handoffAnimation = lib.mkEnableOption "Mickey edge handoff animations on Wayland";
    hideSenderCursor = lib.mkEnableOption "hiding the sender cursor on Hyprland while Mickey forwards input";

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      description = ''
        Mickey TOML settings applied to its writable configuration when the
        service starts. Declared settings take precedence. Other settings and
        pairing state are preserved. Define peers through
        {option}`programs.mickey.peers`.
      '';
    };

    peers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            address = lib.mkOption {
              type = lib.types.strMatching "[^[:space:]]+:[0-9]+";
              example = "desktop.example.org:4242";
              description = "Peer hostname or IP address with its TCP port.";
            };

            position = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.addCheck (lib.types.listOf lib.types.int) (coordinates: builtins.length coordinates == 2)
              );
              default = null;
              example = [
                1920
                120
              ];
              description = ''
                Peer desktop origin as two integers in logical pixels. Null
                leaves its position under Mickey's control.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        Peers to set up by name. Existing pairing keys and other fields are
        preserved. New peers still need interactive pairing.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.settings ? peer);
        message = "Define Mickey peers with programs.mickey.peers.";
      }
    ];

    programs.mickey.settings.updates.check = lib.mkDefault false;

    home.packages = [ cfg.package ];

    systemd.user.services = {
      mickey-cursor = lib.mkIf cfg.hideSenderCursor {
        Unit = {
          Description = "Hide the Hyprland cursor while Mickey forwards input";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = "${lib.getExe pkgs.python3} ${./scripts/mickey-cursor.py}";
          ExecStopPost = "${lib.getExe pkgs.python3} ${./scripts/mickey-cursor.py} --restore";
          Restart = "on-failure";
        };

        Install.WantedBy = [ "graphical-session.target" ];
      };

      mickey-handoff = lib.mkIf cfg.handoffAnimation {
        Unit = {
          Description = "Mickey edge handoff animation";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = "${lib.getExe pkgs.quickshell} -p ${./mickey-handoff.qml}";
          Restart = "on-failure";
        };

        Install.WantedBy = [ "graphical-session.target" ];
      };

      mickey = {
        Unit = {
          Description = "Mickey keyboard and mouse sharing";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          ExecStartPre = "${lib.getExe python} ${./scripts/mickey-config.py} ${lib.escapeShellArg configFile} ${managedSettings}";
          ExecStart = "${lib.getExe cfg.package} run";
          Environment = lib.optional cfg.handoffAnimation "MICKEY_HANDOFF_FILE=%t/mickey-handoff.json";
          Restart = "on-failure";
          RestartSec = 3;
          TimeoutStopSec = 10;
        };

        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
