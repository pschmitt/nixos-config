{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.lan-mouse;
  configPath = "${config.xdg.configHome}/lan-mouse/config.toml";

  # Fingerprints authorize which peers may connect, so they're kept out of
  # the (world-readable) Nix store and injected at activation time from
  # sops instead -- see sops.secrets/sops.templates in `config` below.
  tomlList = values: "[ ${lib.concatMapStringsSep ", " (v: ''"${v}"'') values} ]";

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
in
{
  options.services.lan-mouse = {
    enable = lib.mkEnableOption "lan-mouse (software KVM switch for sharing a mouse/keyboard on the LAN)";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.lan-mouse.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The lan-mouse package to run.";
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

        ${clientsToml}
        [authorized_fingerprints]
        ${fingerprintsToml}
      '';
    };

    systemd.user.services.lan-mouse = {
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

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
