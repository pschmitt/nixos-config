{
  config,
  lib,
  pkgs,
  ...
}:
{
  # FIXME as of 2024-10-21 podman is failing to start more than one container
  # as root
  # Error: netavark: code: 1, msg: iptables: Chain already exists.
  # repro: sudo podman run -ti --rm ghcr.io/pschmitt/debug
  virtualisation.oci-containers.backend = "docker";

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";
    autoPrune = {
      enable = true;
      dates = "daily";
      flags = [ "--all" ];
    };
    # https://docs.docker.com/engine/daemon/live-restore/
    liveRestore = false;
    daemon.settings = {
      ipv6 = true;
      "fixed-cidr-v6" = "fdb4:ec18:af42::/80";
    };
  };

  networking.firewall.trustedInterfaces = lib.mkAfter [ "docker0" ];

  services.monit.checks.dockerd = {
    enable = config.virtualisation.docker.enable;
    type = "program";
    path = "${pkgs.systemd}/bin/systemctl is-active docker";
    group = "docker";
    conditions = "if status > 0 then alert";
  };
}
