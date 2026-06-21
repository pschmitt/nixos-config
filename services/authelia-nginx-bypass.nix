{
  config,
  lib,
  ...
}:
{
  sops.secrets."nginx/ha_ingress_key" = {
    owner = config.services.nginx.user;
  };

  # HA's ingress integration proxies these apps server-side and attaches a
  # shared Bearer token (set via the ingress `headers:` config). nginx skips
  # Authelia when that token is present. The HA *proxy* (not the browser) sends
  # the header, so this works in the HA mobile app too (same-origin iframe, no
  # cookie/WebView dependency).
  sops.templates."nginx/ha-ingress-bypass.conf" = {
    owner = config.services.nginx.user;
    content = ''
      map $http_authorization $authelia_ha_bypass {
        "Bearer ${config.sops.placeholder."nginx/ha_ingress_key"}" 1;
        default                                                      0;
      }
    '';
  };

  # The bypass map key (the ~120-char ha_ingress_key) exceeds nginx's default
  # map_hash_bucket_size and fails to build the map hash ("could not build
  # map_hash"). This option emits map_hash_bucket_size *before* the generated
  # maps (e.g. $http_upgrade); setting it via appendHttpConfig lands it after
  # those maps, which nginx rejects as a duplicate.
  services.nginx.mapHashBucketSize = 256;

  services.nginx.appendHttpConfig = lib.mkAfter ''
    include ${config.sops.templates."nginx/ha-ingress-bypass.conf".path};
  '';
}
