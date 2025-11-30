{ config, pkgs, ... }:
{
  virtualisation.oci-containers.containers.mullvad-net = {
    image = "alpine:latest";
    cmd = [
      "sleep"
      "infinity"
    ];
    autoStart = true;
    extraOptions = [
      # Share the network namespace of the systemd service (which is in the VPN)
      "--network=host"
      "--init"
    ];
  };

  systemd.services."${config.virtualisation.oci-containers.containers.mullvad-net.serviceName
  }".vpnConfinement =
    {
      enable = true;
      vpnNamespace = "mullvad";
    };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "podman-run-mullvad" ''
      exec ${pkgs.podman}/bin/podman run --network container:mullvad-net "$@"
    '')
  ];
}
