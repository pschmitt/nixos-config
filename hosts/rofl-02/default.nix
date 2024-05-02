{ pkgs, ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server

    ./luks-data.nix
    ./rclone-bisync.nix
    ./restic.nix
    ./rsync-fonts-to-rofl-03.nix

    ./monit.nix
    ../../server/luks-ssh-unlock-homelab.nix
  ];

  # Enable networking
  networking = {
    hostName = "rofl-02";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  services.harmonia = {
    enable = true;
    settings = {
      bind = "100.85.145.107:5000";
    };
  };

  systemd.services.docker-compose-bulk-up = {
    after = [ "network.target" "docker.service" "mnt-data.mount" ];
    requires = [ "docker.service" "mnt-data.mount" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk up -d";
    };
  };
}
