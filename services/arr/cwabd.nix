{ config, ... }:
{
  virtualisation.oci-containers.containers.cwabd = {
    image = "ghcr.io/calibrain/calibre-web-automated-book-downloader";
    pull = "always";
    autoStart = true;
    extraOptions = [
      # Use --network=host so the container shares the network namespace of the
      # systemd service, which is confined to the VPN namespace.
      "--network=host"
      "--init"
    ];
  };

  systemd.services."${config.virtualisation.oci-containers.containers.cwabd.serviceName
  }".vpnConfinement =
    {
      enable = true;
      vpnNamespace = "mullvad";
    };
}
