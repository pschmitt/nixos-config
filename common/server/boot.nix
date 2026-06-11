{
  config,
  lib,
  ...
}:
{
  boot.kernel.sysctl = {
    # Raise inotify limits
    "fs.inotify.max_user_instances" = lib.mkForce 524288;
    "fs.inotify.max_user_watches" = lib.mkForce 524288;
  };

  # Write logs to console
  # https://github.com/nix-community/srvos/blob/main/nixos/common/serial.nix
  boot.kernelParams =
    if config.hardware.kvmGuest then
      [
        "console=tty0"
        "console=ttyS0,115200"
      ]
    else
      [ ];

  # boot.kernel.sysctl = {
  #   "net.core.default_qdisc" = "fq";
  #   "net.ipv4.tcp_congestion_control" = "bbr";
  # };
}
