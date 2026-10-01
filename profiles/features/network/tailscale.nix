{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailscalePkg = pkgs.master.tailscale;

  tailscaleFlags = [
    "--advertise-exit-node"
    "--accept-dns"
    "--operator=${config.mainUser.username}"
  ];
in
{
  imports = [ ../../../services/monit/tailscale.nix ];

  sops.secrets."tailscale/auth-key" = {
    restartUnits = [
      "tailscaled-autoconnect.service"
    ];
  };

  services.tailscale = {
    enable = true;
    package = tailscalePkg;
    openFirewall = true;
    extraSetFlags = tailscaleFlags;
    extraUpFlags = tailscaleFlags ++ [ "--reset" ]; # enforce!
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets."tailscale/auth-key".path;
  };

  # HACK Fix netbird port forwarding
  networking = {
    nat.internalInterfaces = [ config.services.tailscale.interfaceName ];
    firewall.trustedInterfaces = lib.mkAfter [
      config.services.tailscale.interfaceName
    ];
  };

  # Hook into tailscaled rather than multi-user.target: autoconnect waits
  # for the Running state, which never happens offline and would otherwise
  # stall multi-user.target until the start timeout.
  # tailscaled-set is ordered after autoconnect, so it must leave
  # multi-user.target too, or it drags the autoconnect timeout back in.
  systemd.services = {
    tailscaled-autoconnect.wantedBy = lib.mkForce [ "tailscaled.service" ];
    tailscaled-set.wantedBy = lib.mkForce [ "tailscaled.service" ];
  };

  # We need to enable route_localnet to allow DNAT to 127.0.0.1.
  # This is used by modules/container-services.nix to redirect traffic
  # from the VPN interface to the container services listening on localhost.
  # We use a udev rule here because the interface is created dynamically
  # and might not exist when systemd-sysctl runs.
  # boot.kernel.sysctl = {
  #   "net.ipv4.conf.${config.services.tailscale.interfaceName}.route_localnet" = 1;
  # };
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", KERNEL=="${config.services.tailscale.interfaceName}", RUN+="${pkgs.procps}/bin/sysctl -w net.ipv4.conf.%k.route_localnet=1"
  '';
}
