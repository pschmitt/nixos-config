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
    "monarch/admin/username" = config.sops.mkHostSecret { };
    "monarch/admin/password" = config.sops.mkHostSecret { };
    "monarch/oidc/client-secret" = config.sops.mkHostSecret { };
    # shared: monit agents report with it (see monit/config/mmonit)
    "monarch/collector/password" = { };
  };

  services.monarch = {
    enable = true;
    package = inputs.monarch.packages.${pkgs.stdenv.hostPlatform.system}.monarch;
    settings = {
      listen = "127.0.0.1:${toString port}";
      public_url = "https://${domain}";
      oidc = {
        # client registered in services/authelia.nix (oidc.yml template)
        issuer = "https://auth.${config.domains.main}";
        client_id = "monarch";
        display_name = "Authelia";
        admin_groups = [ "admin" ];
        # nobody else in Authelia gets in
        default_role = "none";
      };
    };
    oidc.clientSecretFile = config.sops.secrets."monarch/oidc/client-secret".path;
    nginx = {
      enable = true;
      inherit domain;
    };
    ensureUsers = [
      {
        usernameFile = config.sops.secrets."monarch/admin/username".path;
        role = "admin";
        passwordFile = config.sops.secrets."monarch/admin/password".path;
      }
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
