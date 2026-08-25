{
  config,
  lib,
  hostname ? config.home.username,
  pkgs,
  ...
}:
let
  cfg = config.services.ssh-clipboard;
  jsonFormat = pkgs.formats.json { };

  nodeIdHash = builtins.hashString "sha256" "${cfg.nodeName}:${config.home.homeDirectory}";
  generatedNodeId =
    let
      inherit (builtins) substring;
    in
    "${substring 0 8 nodeIdHash}-${substring 8 4 nodeIdHash}-4${substring 13 3 nodeIdHash}-8${substring 17 3 nodeIdHash}-${substring 20 12 nodeIdHash}";

  configFile = jsonFormat.generate "ssh-clipboard-config.json" {
    version = 1;
    node_id = if cfg.nodeId == null then generatedNodeId else cfg.nodeId;
    node_name = cfg.nodeName;
    peers = map (peer: {
      inherit (peer) name;
      ssh_command = peer.sshCommand;
    }) cfg.peers;
    max_bytes = cfg.maxBytes;
    poll_interval_ms = cfg.pollIntervalMs;
    headless_x11 = cfg.headlessX11;
  };

  serviceEnvironment = [
    "PATH=${
      lib.makeBinPath [
        config.home.profileDirectory
        pkgs.bash
        pkgs.bind
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.iproute2
        pkgs.jq
        pkgs.netcat-openbsd
        pkgs.openssh
        pkgs.procps
        cfg.package
      ]
    }"
    "SSH_CLIPBOARD_DISABLE_AUTO_UPDATE=1"
  ]
  ++ lib.optional cfg.headlessX11 "DISPLAY=:99";

  serviceAfter = [
    "network-online.target"
  ]
  ++ lib.optional cfg.headlessX11 "ssh-clipboard-xvfb.service"
  ++ lib.optional (!cfg.headlessX11) "graphical-session.target";

  serviceWants = [
    "network-online.target"
  ]
  ++ lib.optional cfg.headlessX11 "ssh-clipboard-xvfb.service";

  serviceWantedBy = if cfg.headlessX11 then "default.target" else "graphical-session.target";
in
{
  options.services.ssh-clipboard = {
    enable = lib.mkEnableOption "native encrypted clipboard synchronization over SSH";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ssh-clipboard;
      description = "The ssh-clipboard package to run.";
    };

    nodeId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Stable UUID identifying this clipboard node; generated from the host identity when unset.";
    };

    nodeName = lib.mkOption {
      type = lib.types.str;
      default = hostname;
      description = "Human-readable name advertised to clipboard peers.";
    };

    peers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name used for this peer in status output.";
            };

            sshCommand = lib.mkOption {
              type = lib.types.str;
              description = "SSH command used to reach the peer, without a remote command.";
            };
          };
        }
      );
      default = [ ];
      description = "Clipboard peers to connect to persistently over SSH.";
    };

    maxBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 256 * 1024 * 1024;
      description = "Maximum aggregate clipboard payload size.";
    };

    pollIntervalMs = lib.mkOption {
      type = lib.types.ints.between 20 5000;
      default = 75;
      description = "Clipboard polling interval in milliseconds.";
    };

    headlessX11 = lib.mkEnableOption "a private Xvfb clipboard for headless Linux hosts";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.headlessX11 || pkgs ? xorg-server;
        message = "services.ssh-clipboard.headlessX11 requires pkgs.xorg-server";
      }
    ];

    home.packages = [ cfg.package ];

    home.file.".local/bin/ssh-clipboard".source = "${cfg.package}/bin/ssh-clipboard";
    xdg.configFile."ssh-clipboard/config.json".source = configFile;

    systemd.user.services.ssh-clipboard-xvfb = lib.mkIf cfg.headlessX11 {
      Unit.Description = "Private virtual X11 display for ssh-clipboard";
      Service = {
        ExecStart = "${pkgs.xorg-server}/bin/Xvfb :99 -screen 0 1280x720x24 -nolisten tcp -noreset";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.ssh-clipboard = {
      Unit = {
        Description = "Native encrypted clipboard synchronization over SSH";
        After = serviceAfter;
        Wants = serviceWants;
      };
      Service = {
        ExecStart = "${cfg.package}/bin/ssh-clipboard daemon";
        Environment = serviceEnvironment;
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ serviceWantedBy ];
    };
  };
}
