{ inputs, lib, config, pkgs, ... }: {
  systemd.services.hacompanion = {
    enable = true;
    description = "Home Assistant Companion application";
    documentation = [ "https://github.com/tobias-kuendig/hacompanion" ];
    after = [ "NetworkManager-wait-online.service" ];
    path = with pkgs; [ zsh inputs.hyprland.packages.${pkgs.system}.hyprland ];

    serviceConfig = {
      User = "pschmitt";
      EnvironmentFile = "/home/pschmitt/.config/hacompanion/secrets";
      ExecStart = "/home/pschmitt/.local/share/zinit/polaris/bin/hacompanion -config ~/.config/hacompanion/hacompanion.toml";
      Restart = "always";
      RestartSec = 5;
    };

    # For user services
    # wantedBy = [ "default.target" ];
    # For system services
    wantedBy = [ "multi-user.target" ];
  };
}
