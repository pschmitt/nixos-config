{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    inputs.hacompanion.packages.${pkgs.system}.hacompanion
  ];

  systemd.services.hacompanion = {
    enable = true;
    description = "Home Assistant Companion application";
    documentation = [ "https://github.com/tobias-kuendig/hacompanion" ];
    after = [ "NetworkManager-wait-online.service" ];
    path = [
      "${config.custom.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.custom.username}"
    ];

    serviceConfig = {
      User = "${config.custom.username}";
      # NOTE We can't use %E here since we are running as a system service
      EnvironmentFile = "${config.custom.homeDirectory}/.config/hacompanion/secrets";
      ExecStart = "${pkgs.hacompanion}/bin/hacompanion -config ~/.config/hacompanion/hacompanion.toml";
      Restart = "always";
      RestartSec = 5;
    };

    # For user services
    # wantedBy = [ "default.target" ];
    # For system services
    wantedBy = [ "multi-user.target" ];
  };
}
