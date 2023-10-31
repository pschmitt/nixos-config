{ inputs, lib, config, pkgs, ... }:

let username = "pschmitt";

in
{
  environment.systemPackages = with pkgs; [ hacompanion ];

  systemd.services.hacompanion = {
    enable = true;
    description = "Home Assistant Companion application";
    documentation = [ "https://github.com/tobias-kuendig/hacompanion" ];
    after = [ "NetworkManager-wait-online.service" ];
    path = [
      "/home/${username}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${username}"
    ];

    serviceConfig = {
      User = "${username}";
      EnvironmentFile = "/home/${username}/.config/hacompanion/secrets";
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
