{ config, ... }:
let
  # renovate: datasource=docker depName=bellamy/wallos versioning=semver-coerced
  wallosVersion = "5.10.3";
  wallosHost = "subs.${config.domains.main}";
  wallosPort = 8282;
in
{
  sops.secrets."wallos/oidc-client-secret" = config.sops.mkHostSecret { };

  sops.templates."wallos/oidc.env" = {
    content = ''
      OIDC_CLIENT_SECRET=${config.sops.placeholder."wallos/oidc-client-secret"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "${config.virtualisation.oci-containers.backend}-wallos.service" ];
  };

  virtualisation.oci-containers.containers.wallos = {
    image = "bellamy/wallos:${wallosVersion}";
    autoStart = true;
    environmentFiles = [ config.sops.templates."wallos/oidc.env".path ];
    ports = [
      "127.0.0.1:${toString wallosPort}:80"
    ];
    volumes = [
      "/srv/wallos/data/db:/var/www/html/db"
      "/srv/wallos/data/logos:/var/www/html/images/uploads/logos"
    ];
    environment = {
      TZ = config.time.timeZone;
      OIDC_ENABLED = "true";
      OIDC_PROVIDER_NAME = "Authelia";
      OIDC_CLIENT_ID = "wallos";
      OIDC_ISSUER = "https://auth.${config.domains.main}";
      OIDC_REDIRECT_URL = "https://${wallosHost}/index.php";
      OIDC_USER_IDENTIFIER = "sub";
      OIDC_SCOPES = "openid email profile";
      OIDC_AUTO_CREATE_USER = "false";
      OIDC_DISABLE_PASSWORD_LOGIN = "true";
      OIDC_REQUIRE_EMAIL_VERIFIED = "true";
    };
  };

  services.nginx.virtualHosts."${wallosHost}" = {
    authelia.enable = true;
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString wallosPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.checks = {
    wallos = {
      type = "host";
      address = "127.0.0.1";
      group = "container-services";
      restartUnit = "${config.virtualisation.oci-containers.backend}-wallos.service";
      conditions = ''
          with timeout 180 seconds
        if failed
          port ${toString wallosPort}
          protocol http
          with timeout 90 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
      '';
    };
  };
}
