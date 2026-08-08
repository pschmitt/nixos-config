{
  config,
  lib,
  ...
}:
let
  mainDomain = config.domains.main;
  mailHost = "mail.${mainDomain}";
  healthchecksHost = "hc.${mainDomain}";
  publicListen = [
    {
      addr = "0.0.0.0";
      port = 80;
      ssl = false;
    }
    {
      addr = "127.0.0.1";
      port = 8443;
      ssl = true;
    }
  ];

  publicProxy =
    {
      cert,
      backend,
      aliases ? [ ],
      extraConfig ? "",
      proxyHost ? "$host",
      websockets ? false,
    }:
    {
      serverAliases = aliases;
      listen = lib.mkForce publicListen;
      useACMEHost = cert;
      forceSSL = true;
      locations."/" = {
        proxyPass = backend;
        proxyWebsockets = websockets;
        recommendedProxySettings = false;
        extraConfig = ''
          proxy_set_header Host ${proxyHost};
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-Host $host;
          ${extraConfig}
        '';
      };
    };

  brknHosts = [
    mainDomain
    healthchecksHost
    "healthchecks.${mainDomain}"
    "oci-yum.${mainDomain}"
    "traefik.${mainDomain}"
    "ha.${mainDomain}"
    "hass.${mainDomain}"
    "homeassistant.${mainDomain}"
    "home-assistant.${mainDomain}"
  ];
  mailHosts = [
    mailHost
    "mail.pschmitt.dev"
    "stalwart.${mainDomain}"
    "autoconfig.${mainDomain}"
    "autodiscover.${mainDomain}"
    "autoconfig.pschmitt.dev"
    "autodiscover.pschmitt.dev"
  ];
in
{
  security.acme.certs = {
    "oci-01-brkn-lol" = {
      domain = mainDomain;
      extraDomainNames = lib.remove mainDomain brknHosts;
      group = "nginx";
    };
    "oci-01-mail" = {
      domain = mailHost;
      extraDomainNames = lib.remove mailHost mailHosts;
      group = "nginx";
    };
    "oci-01-pschmitt-dev" = {
      domain = "pschmitt.dev";
      extraDomainNames = [ "*.pschmitt.dev" ];
      group = "nginx";
    };
    "oci-01-schmi-tt" = {
      domain = "schmi.tt";
      extraDomainNames = [
        "*.schmi.tt"
        "*.ber.schmi.tt"
        "*.dieppe.schmi.tt"
      ];
      group = "nginx";
    };
    "oci-01-schmitt-co" = {
      domain = "schmitt.co";
      extraDomainNames = [ "*.schmitt.co" ];
      group = "nginx";
    };
    "oci-01-ovm5-de" = {
      domain = "ovm5.de";
      extraDomainNames = [ "*.ovm5.de" ];
      group = "nginx";
    };
  };

  services.nginx = {
    proxyResolveWhileRunning = true;
    resolver = {
      addresses = [ "127.0.0.53" ];
      valid = "30s";
    };

    streamConfig = ''
      map $ssl_preread_protocol $oci_01_public_backend {
        default 127.0.0.1:8443;
        "" 127.0.0.1:22887;
      }

      server {
        listen 443;
        proxy_pass $oci_01_public_backend;
        proxy_timeout 1h;
        ssl_preread on;
      }
    '';

    virtualHosts = {
      "pschmitt.dev" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-pschmitt-dev";
        forceSSL = true;
      };
      "p.schmi.tt" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-schmi-tt";
        forceSSL = true;
      };
      "philipp.schmi.tt" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-schmi-tt";
        forceSSL = true;
      };
      "github.pschmitt.dev" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-pschmitt-dev";
        forceSSL = true;
      };
      "gh.pschmitt.dev" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-pschmitt-dev";
        forceSSL = true;
      };
      "schmitt.co" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-schmitt-co";
        forceSSL = true;
      };

      "${healthchecksHost}" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-brkn-lol";
        forceSSL = true;
      };

      "${mailHost}" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-mail";
        forceSSL = true;
      };

      "autoconfig.schmitt.co" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-schmitt-co";
        forceSSL = true;
      };

      "stalwart.${mainDomain}" = publicProxy {
        cert = "oci-01-mail";
        backend = "http://127.0.0.1:8080";
        aliases = [
          "autoconfig.${mainDomain}"
          "autodiscover.${mainDomain}"
          "autoconfig.pschmitt.dev"
          "autodiscover.pschmitt.dev"
        ];
      };

      "hass.${mainDomain}" = publicProxy {
        cert = "oci-01-brkn-lol";
        backend = "https://2ozir0cxvj1ovgzwcdt0sh49bc0z8lvh.ui.nabu.casa";
        aliases = [
          "ha.${mainDomain}"
          "homeassistant.${mainDomain}"
          "home-assistant.${mainDomain}"
        ];
        websockets = true;
        proxyHost = "2ozir0cxvj1ovgzwcdt0sh49bc0z8lvh.ui.nabu.casa";
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_ssl_name 2ozir0cxvj1ovgzwcdt0sh49bc0z8lvh.ui.nabu.casa;
        '';
      };

      "hass.ber.schmi.tt" = publicProxy {
        cert = "oci-01-schmi-tt";
        backend = "https://2ozir0cxvj1ovgzwcdt0sh49bc0z8lvh.ui.nabu.casa";
        aliases = [
          "ha.ber.schmi.tt"
          "homeassistant.ber.schmi.tt"
          "home-assistant.ber.schmi.tt"
        ];
        websockets = true;
        proxyHost = "2ozir0cxvj1ovgzwcdt0sh49bc0z8lvh.ui.nabu.casa";
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_ssl_name 2ozir0cxvj1ovgzwcdt0sh49bc0z8lvh.ui.nabu.casa;
        '';
      };

      "hass.dieppe.schmi.tt" = publicProxy {
        cert = "oci-01-schmi-tt";
        backend = "http://homeassistant-dieppe.snake-eagle.ts.net:8123";
        aliases = [
          "ha.dieppe.schmi.tt"
          "homeassistant.dieppe.schmi.tt"
          "home-assistant.dieppe.schmi.tt"
        ];
        websockets = true;
      };

      "grafana.ovm5.de" = publicProxy {
        cert = "oci-01-ovm5-de";
        backend = "https://hass.snake-eagle.ts.net:3000";
        aliases = [
          "graphana.ovm5.de"
          "graph.ovm5.de"
          "gr.ovm5.de"
        ];
        websockets = true;
        proxyHost = "hass.snake-eagle.ts.net";
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_ssl_name hass.snake-eagle.ts.net;
        '';
      };

      "oci-yum.${mainDomain}" = publicProxy {
        cert = "oci-01-brkn-lol";
        backend = "https://yum.eu-frankfurt-1.oci.oraclecloud.com";
        proxyHost = "yum.eu-frankfurt-1.oci.oraclecloud.com";
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_ssl_name yum.eu-frankfurt-1.oci.oraclecloud.com;
          proxy_set_header Accept-Encoding "";
          sub_filter 'yum-eu-frankfurt-1.oracle.com' 'oci-yum.${mainDomain}';
          sub_filter_once off;
        '';
      };

      "traefik.${mainDomain}" = {
        listen = lib.mkForce publicListen;
        useACMEHost = "oci-01-brkn-lol";
        forceSSL = true;
        locations."/".return = "410";
      };
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "oci-01-public-https" with address "127.0.0.1"
      group nginx
      group services
      if failed
        port 8443
        protocol https
        with hostheader "pschmitt.dev"
        request "/"
        with timeout 15 seconds
      for 3 cycles
      then alert
  '';
}
