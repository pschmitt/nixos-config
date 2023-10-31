{ inputs, lib, config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [ hacompanion ];

  systemd.services.hacompanion = {
    enable = true;
    description = "Home Assistant Companion application";
    documentation = [ "https://github.com/tobias-kuendig/hacompanion" ];
    after = [ "NetworkManager-wait-online.service" ];
    path = with pkgs; [
      "/home/pschmitt"
      "/run/current-system/sw"
      # alsa-utils
      # inputs.hyprland.packages.${pkgs.system}.hyprland
      # lm_sensors
      # zsh
    ];

    serviceConfig = {
      User = "pschmitt";
      EnvironmentFile = "/home/pschmitt/.config/hacompanion/secrets";
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
