{ config, lib, ... }:
let
  hosts = config.domains.meshHosts "browser";
  meshNodes = [
    "fnuc"
    "rofl-13"
    "rofl-14"
    "rofl-15"
    "rofl-16"
    "lrz"
  ];
  # The names rofl-10's public vhosts (hosts/rofl-10/browserless-public.nix)
  # answer to: a browser sends them as Origin while the vhost rewrites Host.
  # Public share links (/share/<node>/<token>[/<what>]): no login, the daemon
  # checks the token. Only these paths: its other pages hand out a sign-in
  # cookie and rely on Authelia in front.
  shareLocation = "~ ^/share/[A-Za-z0-9_.-]+/[A-Za-z0-9_-]+(/[a-z]+)?$";
  publicNames = [
    "browser.${config.domains.main}"
  ]
  ++ map (h: "browser.${h}.${config.domains.main}") meshNodes
  ++ map (m: "browser.rofl-10.${m}") config.domains.mesh;
  # The SOCKS5 proxy every node offers the mesh (see socksProxy below).
  socksPort = 1080;
  # The HTTP proxy the extensions of paired browsers route their traffic through.
  httpProxyPort = 3128;
  # Closed to everything but the mesh interfaces.
  privatePorts = [
    socksPort
    httpProxyPort
  ];
in
{
  sops.secrets."browser-daemon/cluster-secret" = {
    owner = "browser-daemon";
    group = "browser-daemon";
    mode = "0440";
    # Read once at startup: a rotated secret needs the daemon restarted (its
    # sessions survive that).
    restartUnits = [
      "browser-daemon.service"
    ]
    ++ lib.optional config.services.browser-daemon.secretAgent.enable "browser-daemon-secret-agent.service";
  };

  # The proxies listen on 0.0.0.0 and rely on the mesh interfaces being in
  # networking.firewall.trustedInterfaces (profiles/features/network/): their
  # packets are accepted before extraInputRules is reached, which therefore only
  # sees new connections from other interfaces. Make the deny explicit rather
  # than relying on the port never ending up in allowedTCPPorts. Hosts with the
  # iptables backend (fnuc) ignore extraInputRules: their extraCommands run
  # before the final refuse of the nixos-fw chain.
  networking.firewall = lib.mkMerge [
    (lib.mkIf (config.networking.firewall.backend == "nftables") {
      extraInputRules = lib.concatMapStrings (port: ''
        tcp dport ${toString port} drop
      '') privatePorts;
    })
    (lib.mkIf (config.networking.firewall.backend != "nftables") {
      extraCommands = lib.concatMapStrings (port: ''
        iptables -A nixos-fw -p tcp --dport ${toString port} -j DROP
        ip6tables -A nixos-fw -p tcp --dport ${toString port} -j DROP
      '') privatePorts;
    })
  ];

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
      # Public share links go out under the name the public reaches the mesh by
      # (rofl-10's vhost, see hosts/rofl-10/browserless-public.nix).
      shareUrl = "https://browser.${config.domains.main}";
      # The daemon answers only to its own Host and Origin names (DNS rebinding
      # guard): every name the nginx vhost serves, and the public ones.
      allowedHosts = hosts ++ publicNames;
      # The extension discovers the whole cluster through this list. Include
      # public aliases and each mesh endpoint so every configured entry works.
      extensionOrigins =
        map (host: "https://${host}") (hosts ++ publicNames)
        ++ map (h: "https://browser.${h}.${config.domains.netbird}") meshNodes;
      peers = map (h: "https://browser.${h}.${config.domains.netbird}") meshNodes;
      clusterSecretFile = config.sops.secrets."browser-daemon/cluster-secret".path;
      # An X display per session, streamed to the handoff view as H.264 (x264
      # unless a host has a GPU encoder): under motion ~67% of a core instead of
      # ~147% for the JPEG screencast.
      displayMode = "per-session";
      video.enable = true;
      # POST /api/run: Playwright scripts and steps for clients without
      # Playwright (Home Assistant integrations); cluster secret only.
      run.enable = true;
      # Every node offers its network to the others as a SOCKS5 proxy (`node:<name>`
      # in their proxy lists). Private to the mesh four ways: only the NetBird and
      # Tailscale interfaces are trusted by the firewall (so the port is closed
      # elsewhere, with an explicit drop below), only CG-NAT addresses are
      # answered, and the login is derived from the cluster secret.
      socksProxy = {
        listen = "0.0.0.0:${toString socksPort}";
        allow = [ "100.64.0.0/10" ];
      };
      # The extension of a paired browser routes its traffic through any of the
      # node's proxies (and the peers' `node:<name>`). Private like the SOCKS5
      # proxy: mesh interfaces only, with a login derived from the cluster
      # secret that the extension is handed over its connection. Loopback is
      # allowed for a browser on the node itself.
      httpProxy = {
        # Dual-stack: the mesh names resolve to IPv6 first.
        listen = "[::]:${toString httpProxyPort}";
        # A browser is paired with a public name (browser.<domain>), where the
        # port is closed: it reaches the proxy over the mesh.
        advertise = "browser.${config.networking.hostName}.${config.domains.netbird}";
        allow = [
          "100.64.0.0/10"
          "fd00::/8"
          "127.0.0.0/8"
          "::1"
        ];
      };
    };

    nginx.virtualHosts.${builtins.head hosts} = {
      serverAliases = builtins.tail hosts;
      enableACME = true;
      forceSSL = true;
      authelia = {
        enable = true;
        haIngressBypass = false;
      };

      locations = {
        "= /api/extension/config" = {
          proxyPass = "http://127.0.0.1:3001";
          recommendedProxySettings = true;
          # Public, read-only endpoint used by extension origin discovery.
          authelia = false;
        };
        "= /api/extension/connect" = {
          proxyPass = "http://127.0.0.1:3001";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          # Authenticated by the daemon's origin-bound, single-use pairing
          # code in the first frame. Extensions cannot use Authelia cookies.
          authelia = false;
          extraConfig = ''
            proxy_read_timeout 60s;
            proxy_send_timeout 60s;
          '';
        };
        "/" = {
          proxyPass = "http://127.0.0.1:3001";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          extraConfig = ''
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
          '';
        };
        ${shareLocation} = {
          proxyPass = "http://127.0.0.1:3001";
          recommendedProxySettings = true;
          authelia = false;
          extraConfig = ''
            proxy_read_timeout 3600s;
          '';
        };
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
