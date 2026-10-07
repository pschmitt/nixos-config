{
  config,
  inputs,
  pkgs,
  ...
}:
let
  domain = "monarch.${config.domains.main}";
  port = 8090;
in
{
  imports = [ inputs.monarch.nixosModules.default ];

  sops.secrets = {
    "monarch/admin/password" = config.sops.mkHostSecret { };
    # shared: monit agents report with it (see monit/config/mmonit)
    "monarch/collector/password" = { };
  };

  services.monarch = {
    enable = true;
    package = inputs.monarch.packages.${pkgs.stdenv.hostPlatform.system}.monarch;
    settings = {
      listen = "127.0.0.1:${toString port}";
      public_url = "https://${domain}";
    };
    initialAdmin = {
      user = "admin";
      passwordFile = config.sops.secrets."monarch/admin/password".path;
    };
    nginx = {
      enable = true;
      inherit domain;
    };
    ensureUsers = [
      {
        username = "monit";
        role = "collector";
        passwordFile = config.sops.secrets."monarch/collector/password".path;
      }
    ];
  };

  # FIXME https://github.com/NixOS/nixpkgs/issues/210807
  services.nginx.virtualHosts.${domain}.acmeRoot = null;
}
