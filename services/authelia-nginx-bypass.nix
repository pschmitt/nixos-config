{
  config,
  lib,
  ...
}:
{
  sops.secrets."nginx/ha_ingress_key" = {
    owner = config.services.nginx.user;
  };

  sops.templates."nginx/ha-ingress-bypass.conf" = {
    owner = config.services.nginx.user;
    content = ''
      map $http_authorization $authelia_ha_bypass {
        "Bearer ${config.sops.placeholder."nginx/ha_ingress_key"}" 1;
        default                                                      0;
      }
    '';
  };

  services.nginx.appendHttpConfig = lib.mkAfter ''
    map_hash_bucket_size 128;
    include ${config.sops.templates."nginx/ha-ingress-bypass.conf".path};
  '';
}
