{ config, ... }:
let
  hosts = config.domains.meshHosts "browser";
  meshNodes = [
    "fnuc"
    "rofl-13"
    "rofl-14"
  ];
in
{
  sops.secrets."browser-daemon/cluster-secret" = {
    owner = "browser-daemon";
    group = "browser-daemon";
    mode = "0440";
  };

  services = {
    browser-daemon = {
      enable = true;
      bind = "127.0.0.1:3001";
      maxSessions = 10;
      sessionMemoryMaxMB = 2048;
      memoryMax = "6G";
      cpuQuota = "300%";
      nodeName = config.networking.hostName;
      # NetBird rather than Tailscale: fnuc's Tailscale path loses packets
      # under load (a 170 KB page took ~3 s instead of ~0.3 s), which made
      # screenshots and peer requests crawl.
      publicUrl = "https://browser.${config.networking.hostName}.${config.domains.netbird}";
      peers = map (h: "https://browser.${h}.${config.domains.netbird}") meshNodes;
      clusterSecretFile = config.sops.secrets."browser-daemon/cluster-secret".path;
      # An X display per session, streamed to the handoff view as H.264 (x264
      # unless a host has a GPU encoder): under motion ~67% of a core instead of
      # ~147% for the JPEG screencast.
      displayMode = "per-session";
      video.enable = true;
    };

    nginx.virtualHosts.${builtins.head hosts} = {
      serverAliases = builtins.tail hosts;
      enableACME = true;
      forceSSL = true;
      authelia = {
        enable = true;
        haIngressBypass = false;
      };

      locations."/" = {
        proxyPass = "http://127.0.0.1:3001";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };

    monit.checks.browser-daemon = {
      type = "host";
      address = "127.0.0.1";
      group = "services";
      restartUnit = "browser-daemon.service";
      conditions = ''
        if failed
          port 3001
          protocol http
          request "/health"
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
      '';
    };
  };
}
