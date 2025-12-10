{
  config,
  lib,
  pkgs,
  ...
}:
let
  primaryHost = "wish.${config.domains.main}";
  # hostnames = [
  #   primaryHost
  #   "wishlist.${config.domains.main}"
  #   "wuensche.${config.domains.main}"
  #   "wunschliste.${config.domains.main}"
  # ];
  # serverAliases = lib.remove primaryHost hostnames;
  dataDir = "/mnt/data/srv/wishlist";
  listenPort = 19001;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir}         0750 root root - -"
    "d ${dataDir}/uploads 0750 root root - -"
    "d ${dataDir}/data    0750 root root - -"
  ];

  virtualisation.oci-containers.containers.wishlist = {
    autoStart = true;
    image = "ghcr.io/cmintey/wishlist:latest";
    pull = "always";
    volumes = [
      "${dataDir}/uploads:/usr/src/app/uploads"
      "${dataDir}/data:/usr/src/app/data"
    ];
    environment = {
      # FIXME We can't set an ORIGIN here since we want multiple hostnames
      # https://github.com/cmintey/wishlist/issues/224
      # ... but setting none (or empty) seems to break login
      ORIGIN = "https://${primaryHost}";
      TOKEN_TIME = "72";
      DEFAULT_CURRENCY = "EUR";
    }
    // lib.optionalAttrs (config.time.timeZone != null) {
      TZ = config.time.timeZone;
    };
    ports = [ "127.0.0.1:${toString listenPort}:3280" ];
  };

  services.nginx.virtualHosts."${primaryHost}" = {
    # inherit serverAliases;
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString listenPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      # Mitigate https://github.com/cmintey/wishlist/issues/170 when using nginx
      extraConfig = ''
        proxy_buffer_size         128k;
        proxy_buffers           4 256k;
        proxy_busy_buffers_size   256k;
      '';
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "wishlist" with address "${primaryHost}"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.backend}-wishlist.service"
      if failed
        port 443
        protocol https
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
