{
  config,
  lib,
  pkgs,
  ...
}:
{
  virtualisation = {
    # FIXME as of 2024-10-21 podman is failing to start more than one container
    # as root
    # Error: netavark: code: 1, msg: iptables: Chain already exists.
    # repro: sudo podman run -ti --rm ghcr.io/pschmitt/debug
    oci-containers.backend = "docker";

    podman = {
      enable = true;
      dockerCompat = false;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
      autoPrune = {
        enable = true;
      };
    };

    docker = {
      enable = true;
      storageDriver = "btrfs";
      autoPrune = {
        enable = true;
      };
      # https://docs.docker.com/engine/daemon/live-restore/
      liveRestore = false;
    };
  };

  # XXX Setting the following env vars has the following effect:
  # The env files are loaded, and they MUST EXIST.
  # You might then end up with an error like:
  # $ docker-compose up
  # couldn't find env file: /srv/xxx/.env
  # environment.variables = {
  #   COMPOSE_ENV_FILES = ".env,/etc/containers/env/netbird.env,/etc/containers/env/tailscale.env";
  # };

  environment.systemPackages = with pkgs; [
    podman-compose
  ];

  networking.firewall.trustedInterfaces = lib.mkAfter [ "docker0" ];

  services.monit.config = lib.mkIf (config.virtualisation.oci-containers.backend == "docker") (
    lib.mkAfter ''
      check program "dockerd" with path "${pkgs.systemd}/bin/systemctl is-active docker"
        group docker
        if status > 0 then alert
    ''
  );
}
