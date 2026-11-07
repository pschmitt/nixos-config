# An ad-hoc rworker with the browser stack already in its encrypted image.
{
  config,
  inputs,
  pkgs,
  ...
}:
let
  interface = config.services.netbird.clients.netbird-io.interface;
  daemon = inputs.browser-daemon.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [ ../nixbot-worker ];

  environment.systemPackages = [
    daemon
    pkgs.chromium
    pkgs.xorg-server
    pkgs.xdotool
    pkgs.curl
  ];

  networking.firewall.interfaces.${interface}.allowedTCPPorts = [ 3001 ];

  # /run is tmpfs and, unlike /dev/shm, survives the last SSH logout. The
  # worker owner atomically installs the secret to trigger the service.
  systemd = {
    tmpfiles.rules = [ "d /run/browser-worker 0700 agent users -" ];
    paths.browser-worker = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathExists = "/run/browser-worker/secret";
    };
    services.browser-worker = {
      description = "Browser daemon for an ad-hoc browser worker";
      after = [
        "network-online.target"
        "netbird-netbird-io.service"
      ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.chromium
        pkgs.xorg-server
        pkgs.xdotool
      ];
      serviceConfig = {
        User = "agent";
        Group = "users";
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 2;
      };
      script = ''
        ip=$(${pkgs.iproute2}/bin/ip -4 -o addr show dev ${interface} | ${pkgs.gawk}/bin/awk 'NR == 1 { split($4, a, "/"); print a[1] }')
        test -n "$ip"
        exec ${daemon}/bin/browser-daemon run \
          --bind 0.0.0.0:3001 --public-url http://127.0.0.1:3001 \
          --allowed-host "$ip:3001" --max-sessions 1 --display-mode per-session \
          --profile-dir /home/agent/browser-daemon/profiles \
          --recordings-dir /home/agent/browser-daemon/recordings \
          --cluster-secret-file /run/browser-worker/secret
      '';
    };
  };
}
