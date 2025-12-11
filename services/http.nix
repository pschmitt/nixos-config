{
  config,
  lib,
  pkgs,
  ...
}:
{
  sops.secrets = {
    "cloudflare/email" = { };
    "cloudflare/api_key" = { };
    "htpasswd" = {
      owner = "nginx";
      group = "nginx";
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      inherit (config.mainUser) email;
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      # FIXME we have to forcefully set webroot to null, otherwise a nixpkgs
      # assert will fail
      webroot = null;
      credentialFiles = {
        "CLOUDFLARE_EMAIL_FILE" = config.sops.secrets."cloudflare/email".path;
        "CLOUDFLARE_API_KEY_FILE" = config.sops.secrets."cloudflare/api_key".path;
      };
    };
  };

  services.nginx = {
    enable = true;
    package = pkgs.nginxStable.override { modules = [ pkgs.nginxModules.zstd ]; };

    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;

    # Unlimited file sizes
    clientMaxBodySize = "0";
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
  };

  services.monit.config = lib.mkAfter ''
    check program "nginx" with path "${pkgs.systemd}/bin/systemctl is-active nginx"
      group nginx
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart nginx"
      if status > 0 then restart
      if 5 restarts within 10 cycles then alert
  '';
}
