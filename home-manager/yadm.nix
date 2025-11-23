{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  yadmCloneScript = pkgs.writeShellScript "yadm-clone" ''
    set -euo pipefail

    export GNUPGHOME="${config.home.homeDirectory}/.config/gnupg"
    export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i ${config.home.homeDirectory}/.ssh/hm/id_ed25519"

    echo "Cloning yadm repo (recursive, no bootstrap)"
    ${pkgs.yadm}/bin/yadm clone --recursive --no-bootstrap \
      git@github.com:pschmitt/yadm-config.git

    # FIXME this requires user interaction, so it does not work in the activation script
    # echo "Attempting yadm decrypt"
    # ${pkgs.yadm}/bin/yadm decrypt
  '';
in
{
  systemd.user = {
    services = {
      yadm-clone = {
        Unit = {
          Description = "YADM Clone";
          After = [
            "gpg-import-private.service"
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [
            "gpg-import-private.service"
            "network-online.target"
            "sops-nix.service"
          ];
          ConditionPathExists = "!${config.home.homeDirectory}/.local/share/yadm/repo.git";
        };

        Service = {
          Type = "oneshot";
          ExecStart = yadmCloneScript;
        };

        Install.WantedBy = [ ];
      };

      yadm-pull = {
        Unit = {
          Description = "YADM Pull";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.yadm}/bin/yadm pull --autostash --ff-only --verbose";
        };

        Install.WantedBy = [ ];
      };

      zinit-install = {
        Unit = {
          Description = "zinit install plugins (scheduler burst)";
          After = [ "yadm-clone.service" ];
          Wants = [ "yadm-clone.service" ];
        };

        Service = {
          Type = "oneshot";
          Environment = [
            "TERM=xterm-256color"
            "ZINIT_SCHEDULER_BURST=1"
          ];
          ExecStart = "${pkgs.zsh}/bin/zsh -ils -c -- '@zinit-scheduler burst'";
        };

        Install.WantedBy = [ ];
      };
    };

    timers.yadm-pull = {
      Unit.Description = "YADM Pull";

      Timer = {
        OnCalendar = "*-*-* 00/2:00:00";
        Persistent = true;
      };

      Install.WantedBy = [ "timers.target" ];
    };
  };

  home.activation.yadm-clone = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    export XDG_RUNTIME_DIR=/run/user/${toString osConfig.users.users.${config.home.username}.uid}
    export DBUS_SESSION_BUS_ADDRESS=unix:path=''${XDG_RUNTIME_DIR}/bus

    # NOTE for this work reliably, we need to have lingering enabled for the user
    run ${pkgs.systemd}/bin/systemctl --user start --no-block \
      yadm-clone.service zinit-install.service
  '';
}
