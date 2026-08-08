{
  config,
  lib,
  ...
}:
let
  mainDomain = config.domains.main;
  autoconfigHost = "autoconfig.${mainDomain}";
in
{
  services = {
    go-autoconfig = {
      enable = true;
      settings = {
        service_addr = "127.0.0.1:8081";
        domain = mainDomain;
        imap = {
          server = "imap.gmail.com";
          port = 993;
          socket = "SSL";
        };
        smtp = {
          server = "smtp.gmail.com";
          port = 465;
          socket = "SSL";
        };
      };
    };

    nginx.virtualHosts.${autoconfigHost} = {
      serverAliases = [ "autodiscover.${mainDomain}" ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:8081";
        recommendedProxySettings = true;
      };
    };

    monit.config = lib.mkAfter ''
      check host "go-autoconfig" with address "127.0.0.1"
        group services
        if failed
          port 8081
          protocol http
          with hostheader "${autoconfigHost}"
          request "/mail/config-v1.1.xml"
          with timeout 10 seconds
          for 3 cycles
        then alert
    '';
  };
}
