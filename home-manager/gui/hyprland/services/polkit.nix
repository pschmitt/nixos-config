_: {
  services.hyprpolkitagent.enable = true;

  systemd.user.services.hyprpolkitagent.Service = {
    Restart = "on-failure";
    RestartSec = 5;
  };
}
