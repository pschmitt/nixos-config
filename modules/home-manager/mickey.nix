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
  runtimeFileType = lib.types.nullOr (
    lib.types.addCheck lib.types.str (
      path: lib.hasPrefix "/" path && !lib.hasInfix "\n" path && !lib.hasInfix "\r" path
    )
  );
  credentials = lib.filter (entry: entry.path != null) [
    {
      name = "mickey-config";
      variable = "MICKEY_CONFIG_FILE";
      path = cfg.settingsFile;
    }
    {
      name = "mickey-identity";
      variable = "MICKEY_IDENTITY_FILE";
      path = cfg.identityFile;
    }
    {
      name = "mickey-trusted-peers";
      variable = "MICKEY_TRUSTED_PEERS_FILE";
      path = cfg.trustedPeersFile;
    }
  ];
  executable = lib.getExe cfg.package;
  credentialLauncher = pkgs.writeShellApplication {
    name = "mickey-with-credentials";
    text = ''
      ${lib.concatMapStringsSep "\n" (entry: ''
        export ${entry.variable}="''${CREDENTIALS_DIRECTORY:?}/${entry.name}"
      '') credentials}
      exec ${executable} run
    '';
  };
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
    handoffAnimation = lib.mkEnableOption "the Wayland overlay for Mickey’s optional edge handoff animations";
    awayCursorIndicator = lib.mkEnableOption "a badge beside the visible cursor while Mickey input is elsewhere";

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

    settingsFile = lib.mkOption {
      type = runtimeFileType;
      default = null;
      example = lib.literalExpression ''config.sops.secrets."mickey/config".path'';
      description = ''
        Absolute runtime path to the complete Mickey TOML configuration.
        The service reads a credential snapshot and blocks interactive
        configuration writes. Mutually exclusive with settings and peers.
        A sops-nix secret or rendered template can supply this path.
      '';
    };

    identityFile = lib.mkOption {
      type = runtimeFileType;
      default = null;
      example = lib.literalExpression ''config.sops.secrets."mickey/identity".path'';
      description = ''
        Absolute runtime path to Mickey's raw 32-byte private identity.
        Use a binary secret if provisioned with sops-nix. The service fails
        if the supplied file is missing or invalid.
      '';
    };

    trustedPeersFile = lib.mkOption {
      type = runtimeFileType;
      default = null;
      example = lib.literalExpression ''config.sops.secrets."mickey/trusted-peers".path'';
      description = ''
        Absolute runtime path to the complete incoming trust list, with one
        64-digit hexadecimal public key and an optional note per line.
        Interactive changes to trust are disabled. Restart Mickey after
        replacing any of the runtime files.
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
      {
        assertion = cfg.settingsFile == null || (cfg.settings == { } && cfg.peers == { });
        message = "programs.mickey.settingsFile is mutually exclusive with settings and peers.";
      }
    ];

    programs.mickey.settings = lib.mkIf (cfg.settingsFile == null) {
      updates.check = lib.mkDefault false;
    };

    home.packages = [ cfg.package ];
    home.sessionVariables = lib.listToAttrs (
      map (entry: lib.nameValuePair entry.variable entry.path) credentials
    );

    systemd.user.services = {
      mickey-cursor = lib.mkIf cfg.awayCursorIndicator {
        Unit = {
          Description = "Track Mickey’s away cursor";
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

      mickey-handoff = lib.mkIf (cfg.handoffAnimation || cfg.awayCursorIndicator) {
        Unit = {
          Description = "Mickey handoff visuals";
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
          After = [ "graphical-session.target" ] ++ lib.optional (credentials != [ ]) "sops-nix.service";
        };

        Service = {
          ExecStartPre =
            lib.mkIf (cfg.settingsFile == null)
              "${lib.getExe python} ${./scripts/mickey-config.py} ${lib.escapeShellArg configFile} ${managedSettings}";
          LoadCredential = lib.mkIf (credentials != [ ]) (
            map (entry: "${entry.name}:${lib.replaceStrings [ "%" ] [ "%%" ] entry.path}") credentials
          );
          ExecStart = if credentials == [ ] then "${executable} run" else lib.getExe credentialLauncher;
          Environment =
            lib.optional cfg.handoffAnimation "MICKEY_HANDOFF_FILE=%t/mickey-handoff.json"
            ++ lib.optional cfg.awayCursorIndicator "MICKEY_MANAGE_CURSOR=1";
          Restart = "on-failure";
          RestartSec = 3;
          TimeoutStopSec = 10;
        };

        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
