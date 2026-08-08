{
  lib,
  ...
}:
{
  services = {
    go-autoconfig = {
      enable = true;
      settings = {
        service_addr = "127.0.0.1:8081";
        domain = "schmitt.co";
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

    nginx.virtualHosts."autoconfig.schmitt.co" = {
      serverAliases = [ "autodiscover.schmitt.co" ];
      listen = [
        {
          addr = "0.0.0.0";
          port = 2020;
        }
      ];
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
          with timeout 10 seconds
          for 3 cycles
        then alert
    '';
  };

}
