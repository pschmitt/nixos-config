{
  config,
  lib,
  pkgs,
  inputs,
  hostname,
  ...
}:
let
  cfg = config.services.lan-mouse;
  configPath = "${config.xdg.configHome}/lan-mouse/config.toml";

  # Fingerprints authorize which peers may connect, so they're kept out of
  # the (world-readable) Nix store and injected at activation time from
  # sops instead -- see sops.secrets/sops.templates in `config` below.
  tomlList = values: "[ ${lib.concatMapStringsSep ", " (v: ''"${v}"'') values} ]";

  # enter_hook only fires locally, on the host the mouse is *leaving* (see
  # notifyOnSwitch below) -- lan-mouse has no equivalent hook on the
  # receiving side. We only want a toast for "control just left this host"
  # (not one announcing arrival elsewhere), but the peer's away-sentinel
  # still needs clearing so its own bar icon/panel go quiet -- so still ssh
  # into the peer (same user, key-based, already relied on for `just
  # deploy`), just to clear its sentinel, without firing an osd there. Built
  # as a script (rather than an inline TOML string) so the nested
  # ssh-remote-command quoting doesn't have to survive a TOML string *and*
  # lan-mouse's `sh -c` unescaped -- absolute store paths throughout so
  # neither the local systemd user PATH nor the ssh session's PATH matter
  # (mirrors bluez-headset-callback's approach).
  #
  # lan-mouse also has no way to *query* which side currently owns the
  # cursor (`lan-mouse cli list` only reports whether a client connection is
  # active, not who has input focus) -- so alongside the toast, drop a
  # sentinel file that a consumer (e.g. the noctalia lan-mouse plugin) can
  # poll: present (holding the peer's name) on this host while control is
  # away, absent while it's here. The peer's own hook clears its copy when
  # control arrives there.
  # $XDG_RUNTIME_DIR is inherited from lan-mouse.service's own environment
  # (set by pam_systemd for the user session); the remote side gets it the
  # same way lan-mouse.service does there, via its own login session.
  awaySentinel = "$XDG_RUNTIME_DIR/lan-mouse-away";
  # Complements awaySentinel from the *receiving* side: present (holding the
  # source host's name) on a host while a peer's input is flowing into it,
  # absent otherwise. Lets the noctalia lan-mouse plugin's lockscreen "bring
  # input back" button show up only when it's actually relevant, instead of
  # unconditionally -- see lockscreen.luau. Written remotely below (by the
  # host that's leaving, onto the peer it's entering); cleared locally both
  # here (when *this* host starts sending elsewhere, it can't simultaneously
  # be receiving), in goBackScript (clicking the button is itself "input is
  # back"), and remotely by releaseWatcherScript below (releaseBind's
  # physical key combo bypasses every hook lan-mouse fires, so this is the
  # only other place that ever notices it happened at all).
  incomingSentinel = "$XDG_RUNTIME_DIR/lan-mouse-incoming";
  notifyScript =
    peer:
    pkgs.writeShellScript "lan-mouse-notify-${peer.name}" ''
      rm -f "${incomingSentinel}"
      echo "${peer.name}" > "${awaySentinel}"
      ${pkgs.osd}/bin/osd -a lan-mouse -c lan-mouse -i mouse -t 2000 "Mouse away: ${peer.name}"
      ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=2 ${peer.name} \
        'rm -f "${awaySentinel}"; echo "${hostname}" > "${incomingSentinel}"' &
    '';

  clientsToml = lib.concatMapStringsSep "\n" (peer: ''
    [[clients]]
    hostname = "${peer.name}"
    ips = ${tomlList peer.ips}
    position = "${peer.position}"
    activate_on_startup = ${lib.boolToString peer.activateOnStartup}
    ${lib.optionalString cfg.notifyOnSwitch ''enter_hook = "${notifyScript peer}"''}
  '') cfg.peers;

  fingerprintsToml = lib.concatMapStringsSep "\n" (
    peer: ''"${config.sops.placeholder.${peer.fingerprintSecret}}" = "${peer.name}"''
  ) cfg.peers;

  # `releaseBind` is the real fix for "stuck on a locked peer" (see its own
  # comment), but it needs the physical keyboard, which not everyone reaches
  # for. This gives the noctalia lan-mouse plugin's lockscreen widget the
  # same escape hatch as a click.
  #
  # Went through worse designs first, both confirmed live 2026-09-17:
  # - `lan-mouse cli deactivate`+`activate` on the specific client (on the
  #   peer, over ssh) left that peer's daemon silently skipping enter_hook
  #   on the *next* real capture into it -- capture itself kept working,
  #   just without ever notifying anyone.
  # - restarting only the *peer's* service over ssh (no local restart) fixed
  #   that, but the release still depended on ssh reaching the peer at
  #   exactly the right moment, and the away side still went stale on its
  #   own at least once more.
  #
  # Restarting *this* host's own lan-mouse.service needs no ssh for the
  # release itself: killing this end's connection is what the peer's own
  # daemon already treats as "releasing capture: not connected" (seen live
  # in its logs on ordinary disconnects) -- the exact same clean release
  # path a real disconnect takes. Restarting the *peer's* service too, in
  # parallel over ssh, is redundant belt-and-suspenders on top of that (not
  # required for the release itself, which this end's own restart already
  # guarantees) -- cheap insurance since both ends drop the same
  # connection either way, and it doubles as the moment to also clear the
  # peer's own awaySentinel file, so its bar icon doesn't stay stuck
  # showing "away: <this host>" once the connection re-establishes via
  # `activate_on_startup`.
  goBackScript = pkgs.writeShellScript "lan-mouse-go-back" ''
    rm -f "${incomingSentinel}"
    systemctl --user restart lan-mouse.service &
    for peer in ${lib.concatMapStringsSep " " (p: p.name) cfg.peers}; do
      ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=2 "$peer" \
        'systemctl --user restart lan-mouse.service; rm -f "${awaySentinel}"' &
    done
    wait
  '';

  # `releaseBind` forces capture back entirely inside lan-mouse's own
  # capture backend, before events are forwarded -- it never runs
  # enter_hook or anything else external, so neither sentinel above ever
  # updates when it's used (confirmed live: bar icon/lockscreen button
  # left stuck). lan-mouse exposes no hook, IPC event stream, or `cli`
  # subcommand for this (checked: `cli --help` has no watch/events/status
  # verb, and the daemon logs "releasing capture: release-bind pressed"
  # with nothing else configurable around it) -- the journal line is the
  # only externally observable signal at all. This tails this host's own
  # lan-mouse.service journal continuously and reacts to that exact line:
  # clears this host's own awaySentinel (control is back locally) and, over
  # ssh, clears every peer's incomingSentinel -- the same bookkeeping
  # goBackScript does, just triggered by the log line instead of a click.
  releaseWatcherScript = pkgs.writeShellScript "lan-mouse-release-watcher" ''
    ${pkgs.systemd}/bin/journalctl --user -u lan-mouse.service -f -n 0 -o cat | while IFS= read -r line; do
      case "$line" in
        *"releasing capture: release-bind pressed"*)
          rm -f "${awaySentinel}"
          for peer in ${lib.concatMapStringsSep " " (p: p.name) cfg.peers}; do
            ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=2 "$peer" \
              'rm -f "${incomingSentinel}"' &
          done
          wait
          ;;
      esac
    done
  '';

  peerNames = lib.concatMapStringsSep " " (peer: lib.escapeShellArg peer.name) cfg.peers;
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
      # lan-mouse fires this per-client "enter hook" locally as the mouse
      # leaves this host to enter that peer's screen, so it's the natural
      # place to surface "your input now lives on <peer>" -- there's no
      # equivalent hook for the mouse coming back (see enter_hook in
      # https://github.com/feschber/lan-mouse). We piggyback an ssh call to
      # the peer so both screens get a toast, not just the one being left.
      # `releaseBind` below is the way back to this host.
      default = true;
      description = "Show an OSD notification (via osd(1)) on both this host and the peer when the mouse switches between them.";
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

    xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter ''
      lan-mouse::_control() {
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
      }

      lan-mouse::start() {
        lan-mouse::_control start
      }

      lan-mouse::stop() {
        lan-mouse::_control stop
      }

      lan-mouse::restart() {
        local failed=0

        lan-mouse::_control stop || failed=1
        lan-mouse::_control start || failed=1

        return "$failed"
      }
    '';

    # Stable path (unlike goBackScript's own store path, which changes every
    # generation) for the noctalia lan-mouse plugin's lockscreen widget to
    # exec directly.
    home.file.".config/lan-mouse/go-back".source = goBackScript;

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

      Install.WantedBy = lib.optionals cfg.autoStart [ "graphical-session.target" ];
    };

    # See releaseWatcherScript's own comment: the only way to react to
    # release_bind at all is tailing lan-mouse.service's own journal.
    # `PartOf = [ "lan-mouse.service" ]` propagates both stop *and* restart
    # from lan-mouse.service to this unit (goBackScript restarts
    # lan-mouse.service directly, which would otherwise leave this tailing
    # a now-dead journalctl stream from the old process).
    systemd.user.services.lan-mouse-release-watcher = {
      Unit = {
        Description = "Clears lan-mouse sentinels when release_bind forces capture back";
        After = [ "lan-mouse.service" ];
        PartOf = [ "lan-mouse.service" ];
      };

      Service = {
        ExecStart = "${releaseWatcherScript}";
        Restart = "on-failure";
        RestartSec = 1;
      };

      Install.WantedBy = [ "lan-mouse.service" ];
    };
  };
}
