{
  config,
  lib,
  ...
}:
{
  sops.secrets."nginx/ha_ingress_key" = {
    owner = config.services.nginx.user;
  };

  # Bypass keyed on a cookie rather than the Authorization header: browsers
  # cannot attach custom headers to an <iframe> navigation, but they DO send
  # cookies on same-site iframe loads. HA sets this cookie on domain=brkn.lol,
  # so the HA sidebar can iframe the *arr apps directly (no proxy, no SPA
  # sub-path breakage) and still skip the Authelia login.
  sops.templates."nginx/ha-ingress-bypass.conf" = {
    owner = config.services.nginx.user;
    content = ''
      map $cookie_ha_ingress $authelia_ha_bypass {
        "${config.sops.placeholder."nginx/ha_ingress_key"}" 1;
        default                                              0;
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
