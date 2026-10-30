{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.lan-mouse;
  configPath = "${config.xdg.configHome}/lan-mouse/config.toml";

  # Fingerprints authorize which peers may connect, so they're kept out of
  # the (world-readable) Nix store and injected at activation time from
  # sops instead -- see sops.secrets/sops.templates in `config` below.
  tomlList = values: "[ ${lib.concatMapStringsSep ", " (v: ''"${v}"'') values} ]";

  # Notifications subscribe to local daemon snapshots/events. They do not
  # write widget state or contact another host.
  notificationHelper = pkgs.writeShellApplication {
    name = "lan-mouse-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glib
      pkgs.libnotify
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/lan-mouse-notify.sh;
  };
  stateNotifyScript = pkgs.writeText "lan-mouse-state-notify.py" (
    builtins.readFile ./scripts/lan-mouse-state-notify.py
  );
  goBackScript = pkgs.writeShellApplication {
    name = "lan-mouse-go-back";
    runtimeInputs = [ pkgs.systemd ];
    text = "systemctl --user restart lan-mouse.service";
  };

  clientsToml = lib.concatMapStringsSep "\n" (peer: ''
    [[clients]]
    hostname = "${peer.name}"
    ips = ${tomlList peer.ips}
    position = "${peer.position}"
    activate_on_startup = ${lib.boolToString peer.activateOnStartup}
  '') cfg.peers;

  fingerprintsToml = lib.concatMapStringsSep "\n" (
    peer: ''"${config.sops.placeholder.${peer.fingerprintSecret}}" = "${peer.name}"''
  ) cfg.peers;

  hotEdgePeer = lib.findFirst (
    peer: peer.position == "left" || peer.position == "right"
  ) null cfg.peers;
  hotEdge = if cfg.hotEdge.edge != null then cfg.hotEdge.edge else hotEdgePeer.position;

  peerNames = lib.concatMapStringsSep " " (peer: lib.escapeShellArg peer.name) cfg.peers;
in
{
  options.services.lan-mouse = {
    enable = lib.mkEnableOption "lan-mouse (software KVM switch for sharing a mouse/keyboard on the LAN)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.lan-mouse;
      description = "The lan-mouse package to run.";
    };

    inputKeymapFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "XKB keymap used by Lan Mouse's virtual keyboard for incoming remote input.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4242;
      description = "Listen port for lan-mouse.";
    };

    captureBackend = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "input-capture-portal"
          "layer-shell"
          "x11"
          "dummy"
        ]
      );
      # input-capture-portal (lan-mouse's auto-detected default on wlroots
      # compositors) drops CTRL/SHIFT/ALT/SUPER modifier events when the
      # receiving end uses the wlroots emulation backend -- a known
      # upstream limitation (https://github.com/feschber/lan-mouse). Force
      # layer-shell, which Hyprland supports natively and doesn't have
      # this bug.
      default = "layer-shell";
      description = "Input capture backend override (--capture-backend). Null uses lan-mouse's auto-detection.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether lan-mouse.service starts automatically via
        graphical-session.target. When false, the package, config and
        systemd units are still deployed -- only the automatic start is
        skipped, so it can still be started manually with
        `systemctl --user start lan-mouse.service`.
      '';
    };

    notifyOnSwitch = lib.mkOption {
      type = lib.types.bool;
      # Subscribe to acknowledged outgoing routing and release events over
      # local IPC, independently of the Noctalia widget.
      default = true;
      description = "Show a desktop notification on the host whose mouse switches to a peer.";
    };

    releaseBind = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      # lan-mouse scancode names (e.g. "KeyLeftCtrl"); held together they
      # force input capture back to this host regardless of where the
      # cursor logically is. Null keeps lan-mouse's own upstream default
      # (KeyLeftCtrl + KeyLeftShift + KeyLeftMeta + KeyLeftAlt).
      #
      # Not just a convenience shortcut: it's the *only* way back once the
      # peer's session is locked. lan-mouse normally releases capture by
      # watching the cursor cross back over the screen edge on the
      # receiving (peer) side, but a session lock there grabs input
      # exclusively, so that edge-crossing check never fires -- confirmed
      # 2026-09-17 with gk4 locked while ge2 held the mouse. release_bind
      # is evaluated locally on the *capturing* host (ge2, still reading
      # the physical keyboard) before events are forwarded, so it works
      # regardless of what the peer's session is doing.
      default = null;
      description = "Key combination (release_bind) that forces input capture back to this host. Null uses lan-mouse's default.";
    };

    hotEdge = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = hotEdgePeer != null;
        defaultText = lib.literalExpression "true if a peer sits to the left or right";
        description = ''
          Show a small button when the pointer hits the middle of the screen
          edge facing a peer while lan-mouse is not running; clicking it runs
          `lan-mouse::start`.
        '';
      };

      edge = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "left"
            "right"
          ]
        );
        default = null;
        description = "Screen edge for the hot zone. Null uses the position of the first left/right peer.";
      };
    };

    peers = lib.mkOption {
      default = [ ];
      description = "lan-mouse peers to connect to.";
      type = lib.types.listOf (
        lib.types.submodule (
          { config, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Peer hostname, as resolved on the LAN.";
              };

              position = lib.mkOption {
                type = lib.types.enum [
                  "left"
                  "right"
                  "top"
                  "bottom"
                ];
                description = "Screen-edge position of this peer relative to this host.";
              };

              fingerprintSecret = lib.mkOption {
                type = lib.types.str;
                default = "lan-mouse/${config.name}-fingerprint";
                description = ''
                  sops secret name holding this peer's SHA256 TLS certificate
                  fingerprint. Declared automatically in sops.secrets below.
                '';
              };

              ips = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Static IPs to try for this peer, in addition to DNS resolution.";
              };

              activateOnStartup = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to activate this peer connection on lan-mouse startup.";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    # Exposes `lan-mouse cli ...` on PATH -- used interactively, and by the
    # noctalia lan-mouse plugin (pschmitt/noctalia-plugins) to list peers.
    home.packages = [ cfg.package ];

    # Autoloaded: one file per function in share/zsh/site-functions.
    programs.zsh.siteFunctions = {
      "lan-mouse::_control" = ''
        local action="$1"
        local peer
        local failed=0

        if ! systemctl --user "$action" lan-mouse.service
        then
          printf 'Failed to %s lan-mouse.service locally\n' "$action" >&2
          failed=1
        fi

        for peer in ${peerNames}
        do
          if ! ssh -o BatchMode=yes -o ConnectTimeout=2 "$peer" \
            systemctl --user "$action" lan-mouse.service
          then
            printf 'Failed to %s lan-mouse.service on %s\n' "$action" "$peer" >&2
            failed=1
          fi
        done

        return "$failed"
      '';
      "lan-mouse::start" = "lan-mouse::_control start";
      "lan-mouse::stop" = "lan-mouse::_control stop";
      "lan-mouse::restart" = "lan-mouse::_control restart";
    };

    # Stable path (unlike goBackScript's own store path, which changes every
    # generation) for the noctalia lan-mouse plugin's lockscreen widget to
    # exec directly.
    home.file.".config/lan-mouse/go-back".source = "${goBackScript}/bin/lan-mouse-go-back";

    sops.secrets = builtins.listToAttrs (
      map (peer: {
        name = peer.fingerprintSecret;
        value = { };
      }) cfg.peers
    );

    sops.templates."lan-mouse-config" = {
      path = configPath;
      mode = "0600";
      content = ''
        port = ${toString cfg.port}
        ${lib.optionalString (cfg.releaseBind != null) "release_bind = ${tomlList cfg.releaseBind}\n"}
        ${clientsToml}
        [authorized_fingerprints]
        ${fingerprintsToml}
      '';
    };

    systemd.user.services = {
      lan-mouse = {
        Unit = {
          Description = "lan-mouse - software KVM switch for sharing a mouse/keyboard on the LAN";
          After = [
            "graphical-session.target"
            "sops-nix.service"
          ];
          Wants = [ "sops-nix.service" ];
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          Environment = lib.optional (cfg.inputKeymapFile != null) "LAN_MOUSE_KEYMAP=${cfg.inputKeymapFile}";
          ExecStart = lib.concatStringsSep " " (
            [ "${cfg.package}/bin/lan-mouse" ]
            ++ lib.optionals (cfg.captureBackend != null) [
              "--capture-backend"
              cfg.captureBackend
            ]
            ++ [ "daemon" ]
          );
          Restart = "on-failure";
          RestartSec = 1;
        };

        Install.WantedBy = lib.optionals cfg.autoStart [ "graphical-session.target" ];
      };

      lan-mouse-hot-edge = lib.mkIf cfg.hotEdge.enable {
        Unit = {
          Description = "Offer to start lan-mouse when the pointer hits the ${hotEdge} screen edge";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          Environment = [
            "LAN_MOUSE_HOT_EDGE=${hotEdge}"
            # lan-mouse::start is a zsh function: local daemon plus peers over ssh.
            "PATH=${
              lib.makeBinPath [
                pkgs.bash
                pkgs.coreutils
                pkgs.zsh
                pkgs.systemd
                pkgs.openssh
              ]
            }"
          ];
          ExecStart = "${pkgs.quickshell}/bin/quickshell -p ${./lan-mouse-hot-edge.qml}";
          Restart = "on-failure";
        };

        Install.WantedBy = [ "graphical-session.target" ];
      };

      lan-mouse-state-notify = lib.mkIf cfg.notifyOnSwitch {
        Unit = {
          Description = "Lan Mouse notifications from local input state";
          After = [ "lan-mouse.service" ];
          PartOf = [ "lan-mouse.service" ];
        };

        Service = {
          ExecStart = "${lib.getExe pkgs.python3} ${stateNotifyScript} ${notificationHelper}/bin/lan-mouse-notify";
          ExecStopPost = "${notificationHelper}/bin/lan-mouse-notify dismiss";
          Restart = "always";
          RestartSec = 1;
        };

        Install.WantedBy = [ "lan-mouse.service" ];
      };
    };
  };
}
