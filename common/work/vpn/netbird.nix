{ ... }: {
  services.netbird.enable = true;

  systemd.services.netbird-wt0.after = [ "tailscaled.service" ];
}
