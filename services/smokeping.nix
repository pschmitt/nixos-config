{
  config,
  pkgs,
  ...
}:
let
  smokepingDataDir = "/srv/smokeping/data";
  smokepingPort = 36960;
  smokepingMeshHosts = config.domains.meshHosts "smokeping";
  smokepingHost = builtins.head smokepingMeshHosts;
  smokepingAliases = builtins.tail smokepingMeshHosts;
  autheliaConfig = import ./authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };
in
{
  services.smokeping = {
    enable = true;
    hostName = "${config.networking.hostName}.lan";
    owner = "Philipp Schmitt";
    ownerEmail = "philipp@schmitt.co";
    host = "smokeping";
    probeConfig = ''
      + FPing
      binary = ${config.security.wrapperDir}/fping

      + FPing6
      binary = ${config.security.wrapperDir}/fping
      protocol = 6

      + DNS
      binary = ${pkgs.dnsutils}/bin/dig
      lookup = google.com
      pings = 5
      step = 300
    '';
    targetConfig = ''
      probe = FPing

      menu = Top
      title = Network Latency Grapher
      remark = Welcome to SmokePing. \
               Here you will learn all about the latency of our network.

      + InternetSites

      menu = Internet Sites
      title = Internet Sites

      ++ Facebook
      menu = Facebook
      title = Facebook
      host = facebook.com

      ++ Youtube
      menu = YouTube
      title = YouTube
      host = youtube.com

      ++ JupiterBroadcasting
      menu = JupiterBroadcasting
      title = JupiterBroadcasting
      host = jupiterbroadcasting.com

      ++ GoogleSearch
      menu = Google
      title = google.com
      host = google.com

      ++ GoogleSearchIpv6
      menu = Google
      probe = FPing6
      title = ipv6.google.com
      host = ipv6.google.com

      ++ linuxserverio
      menu = linuxserver.io
      title = linuxserver.io
      host = linuxserver.io

      + Europe

      menu = Europe
      title = European Connectivity

      ++ Germany

      menu = Germany
      title = The Fatherland

      +++ TelefonicaDE

      menu = Telefonica DE
      title = Telefonica DE
      host = www.telefonica.de

      ++ Switzerland

      menu = Switzerland
      title = Switzerland

      +++ CernIXP

      menu = CernIXP
      title = Cern Internet eXchange Point
      host = cixp.web.cern.ch

      +++ SBB

      menu = SBB
      title = SBB
      host = www.sbb.ch

      ++ UK

      menu = United Kingdom
      title = United Kingdom

      +++ CambridgeUni

      menu = Cambridge
      title = Cambridge
      host = cam.ac.uk

      +++ UEA

      menu = UEA
      title = UEA
      host = uea.ac.uk

      + USA

      menu = North America
      title = North American Connectivity

      ++ MIT

      menu = MIT
      title = Massachusetts Institute of Technology Webserver
      host = web.mit.edu

      ++ UCB

      menu = U. C. Berkeley
      title = U. C. Berkeley Webserver
      host = www.berkeley.edu

      ++ UCSD

      menu = U. C. San Diego
      title = U. C. San Diego Webserver
      host = ucsd.edu

      ++ UMN

      menu =  University of Minnesota
      title = University of Minnesota
      host = twin-cities.umn.edu

      ++ OSUOSL

      menu = Oregon State University Open Source Lab
      title = Oregon State University Open Source Lab
      host = osuosl.org

      + DNS
      menu = DNS
      title = DNS

      ++ GoogleDNS1
      menu = Google DNS 1
      title = Google DNS 8.8.8.8
      host = 8.8.8.8

      ++ GoogleDNS2
      menu = Google DNS 2
      title = Google DNS 8.8.4.4
      host = 8.8.4.4

      ++ OpenDNS1
      menu = OpenDNS1
      title = OpenDNS1
      host = 208.67.222.222

      ++ OpenDNS2
      menu = OpenDNS2
      title = OpenDNS2
      host = 208.67.220.220

      ++ CloudflareDNS1
      menu = Cloudflare DNS 1
      title = Cloudflare DNS 1.1.1.1
      host = 1.1.1.1

      ++ CloudflareDNS2
      menu = Cloudflare DNS 2
      title = Cloudflare DNS 1.0.0.1
      host = 1.0.0.1

      ++ L3-1
      menu = Level3 DNS 1
      title = Level3 DNS 4.2.2.1
      host = 4.2.2.1

      ++ L3-2
      menu = Level3 DNS 2
      title = Level3 DNS 4.2.2.2
      host = 4.2.2.2

      ++ Quad9
      menu = Quad9
      title = Quad9 DNS 9.9.9.9
      host = 9.9.9.9

      + DNSProbes
      menu = DNS Probes
      title = DNS Probes
      probe = DNS

      ++ GoogleDNS1
      menu = Google DNS 1
      title = Google DNS 8.8.8.8
      host = 8.8.8.8

      ++ GoogleDNS2
      menu = Google DNS 2
      title = Google DNS 8.8.4.4
      host = 8.8.4.4

      ++ OpenDNS1
      menu = OpenDNS1
      title = OpenDNS1
      host = 208.67.222.222

      ++ OpenDNS2
      menu = OpenDNS2
      title = OpenDNS2
      host = 208.67.220.220

      ++ CloudflareDNS1
      menu = Cloudflare DNS 1
      title = Cloudflare DNS 1.1.1.1
      host = 1.1.1.1

      ++ CloudflareDNS2
      menu = Cloudflare DNS 2
      title = Cloudflare DNS 1.0.0.1
      host = 1.0.0.1

      ++ L3-1
      menu = Level3 DNS 1
      title = Level3 DNS 4.2.2.1
      host = 4.2.2.1

      ++ L3-2
      menu = Level3 DNS 2
      title = Level3 DNS 4.2.2.2
      host = 4.2.2.2

      ++ Quad9
      menu = Quad9
      title = Quad9 DNS 9.9.9.9
      host = 9.9.9.9
    '';
  };

  # Bind mount /srv/smokeping/data to /var/lib/smokeping/data so historical RRDs are preserved
  fileSystems."/var/lib/smokeping/data" = {
    device = smokepingDataDir;
    fsType = "none";
    options = [ "bind" ];
  };

  systemd.tmpfiles.rules = [
    "d ${smokepingDataDir} 0750 smokeping smokeping -"
    "Z ${smokepingDataDir} 0750 smokeping smokeping -"
  ];

  # Keep the existing direct listener for local and legacy access, and add
  # standard HTTPS endpoints on the mesh networks.
  services.nginx.virtualHosts = {
    "smokeping".listen = [
      {
        addr = "0.0.0.0";
        port = smokepingPort;
      }
    ];

    ${smokepingHost} = {
      serverAliases = smokepingAliases;
      enableACME = true;
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString smokepingPort}";
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ smokepingPort ];
}
