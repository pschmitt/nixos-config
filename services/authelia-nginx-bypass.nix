{
  config,
  lib,
  ...
}:
let
  forceBypassHeaderSecret = config.custom.authelia.forceBypassHeaderSecret;
  forceBypassMapEntry = lib.optionalString (forceBypassHeaderSecret != null) ''
    "${config.sops.placeholder.${forceBypassHeaderSecret}}" 1;
  '';
in
{
  options.custom.authelia.forceBypassHeaderSecret = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      Name of the SOPS secret whose exact value in the X-Authelia-Bypass
      header bypasses Authelia on nginx vhosts using the standard auth-request
      snippet. This is a bearer credential and should only be enabled for a
      host where that risk is understood.
    '';
  };

  config = {
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
        map $http_x_authelia_bypass $authelia_force_header_bypass {
          ${forceBypassMapEntry}
          default 0;
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
  };
}
