{ config, ... }:
{
  virtualisation.oci-containers.containers.cwabd = {
    image = "ghcr.io/calibrain/calibre-web-automated-book-downloader";
    autoStart = true;
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  systemd.services."${config.virtualisation.oci-containers.containers.cwabd.serviceName}" = {
    after = [ "mullvad.service" ];
    requires = [ "mullvad.service" ];
  };
}
