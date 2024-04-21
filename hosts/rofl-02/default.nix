{ pkgs, ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server

    ./luks-data.nix
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
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "docker.service" "mnt-data.mount" ];
    requires = [ "docker.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk up -d";
    };
  };
}
