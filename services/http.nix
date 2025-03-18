{ config, pkgs, ... }:
{
  sops.secrets = {
    "cloudflare/email" = { };
    "cloudflare/api_key" = { };
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = config.custom.email;
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
    # recommendedGzipSettings = true;
    recommendedZstdSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
  };
}
