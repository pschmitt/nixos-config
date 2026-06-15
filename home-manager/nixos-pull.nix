{ config, pkgs, ... }:
{
  systemd.user = {
    services.nixos-pull = {
      Unit = {
        Description = "NixOS config git pull";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "oneshot";
        Environment = [
          "GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh -i ${config.home.homeDirectory}/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"
        ];
        ExecStart = "${pkgs.git}/bin/git -C /etc/nixos pull --ff-only --autostash --verbose";
      };

      Install.WantedBy = [ "default.target" ];
    };

    timers.nixos-pull = {
      Unit.Description = "NixOS config git pull timer";

      Timer = {
        OnUnitInactiveSec = "2h";
        Persistent = true;
      };

      Install.WantedBy = [ "timers.target" ];
    };
  };
}
