{ ... }: {
  services.netbird.enable = true;

  # Starting netbird before tailscaled ensures that (tailscale) hosts
  # resolution works as expected.
  systemd.services.netbird-wt0.after = [ "tailscaled.service" ];
}
