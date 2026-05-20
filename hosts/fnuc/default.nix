{ config, pkgs, ... }:
let
  # Use .claude-wrapped to bypass the HM wrapper that prepends --plugin-dir,
  # which remote-control does not accept as an argument.
  claudeBin = "${config.programs.claude-code.finalPackage}/bin/.claude-wrapped";
  claudeRemoteControlStart = pkgs.writeShellScript "claude-remote-control-start" ''
    exec ${claudeBin} remote-control \
      --name fnuc-svc \
      --permission-mode bypassPermissions
  '';
in
{
  imports = [
    ../../modules/main-user.nix
    ../../modules/domains.nix

    ../../home-manager/base.nix
    ../../home-manager/work
    ../../home-manager/sops-standalone.nix
  ];

  domains.main = "brkn.lol";

  targets.genericLinux.enable = true;

  home = {
    inherit (config.mainUser) username homeDirectory;
    stateVersion = "26.05";
  };

  systemd.user.services.claude-remote-control = {
    Unit = {
      Description = "Claude Code remote control server";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${claudeRemoteControlStart}";
      Restart = "on-failure";
      RestartSec = "10s";
      WorkingDirectory = "%h";
      StandardInput = "null";
      StandardOutput = "append:${config.home.homeDirectory}/.local/state/claude-remote-control.log";
      StandardError = "journal";
    };
    Install.WantedBy = [ "default.target" ];
  };

  services.home-manager.autoUpgrade = {
    enable = true;
    frequency = "02:30";
    useFlake = true;
    flakeDir = "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";
    flags = [
      "-b"
      "hm-backup"
    ];
    preSwitchCommands = [
      "${pkgs.gitMinimal}/bin/git pull"
    ];
  };
}
