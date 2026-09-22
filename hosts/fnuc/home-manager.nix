{ config, inputs, ... }:
{
  home-manager.users.${config.mainUser.username} =
    { config, pkgs, ... }:
    {
      imports = [
        ../../home-manager/gui/go-hass-agent
        ../../modules/home-manager/claude-remote-control.nix
        ../../modules/home-manager/codex-remote-control.nix
        inputs.codex-ha-bridge.homeManagerModules.default
        ../../home-manager/ssh-clipboard-peers.nix
        ../../services/nix-distributed-build.nix

        ./claude-work-warmup.nix
        ./agy-warmup.nix
      ];

      services = {
        ssh-clipboard = {
          headlessX11 = true;
          sessionDisplay = ":99";
        };

        codex-ha-bridge = {
          enable = true;
          environmentFile = config.sops.secrets."codex-ha-bridge/env".path;
        };

        go-hass-agent = {
          enable = true;
          enableDesktopScripts = false;
          mqttUsernameSecret = "home-assistant/mqtt/username";
          mqttPasswordSecret = "home-assistant/mqtt/password";
          scriptPackages = with pkgs; [
            jq
            rbw
          ];
        };
      };

      xdg.configFile."home-manager".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";

      systemd.user = {
        services.kubeconfig-update = {
          Unit.Description = "Update kubeconfigs";
          Service = {
            Type = "oneshot";
            ExecStartPre = "${config.home.homeDirectory}/bin/zhj rancher::login-cli-all";
            ExecStart = "${config.home.homeDirectory}/bin/zhj kubectl::kubeconfig-export-rancher";
          };
        };

        timers.kubeconfig-update = {
          Unit.Description = "Periodically update kubeconfigs";
          Timer = {
            OnCalendar = "12:30:00";
            RandomizedDelaySec = "30m";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };

      nix.settings.max-jobs = 0;

      sops.secrets = {
        "codex-ha-bridge/env".mode = "0600";
        "ssh/nix-remote-builder/privkey".mode = "0400";
      };
    };
}
