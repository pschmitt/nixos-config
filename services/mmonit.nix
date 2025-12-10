{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [ mmonit ];
  systemd.packages = [ pkgs.mmonit ];
  systemd.services.mmonit.wantedBy = lib.mkForce [ "multi-user.target" ];

  users.users.mmonit = {
    isSystemUser = true;
    home = "/var/lib/mmonit";
    createHome = true;
    group = "mmonit";
  };
  users.groups.mmonit = { };

  # license
  sops.secrets."mmonit/license" = {
    inherit (config.custom) sopsFile;
    owner = "mmonit";
  };

  environment.etc."mmonit/license.xml".source = "${config.sops.secrets."mmonit/license".path}";

  services.nginx.virtualHosts =
    let
      commonConfig = {
        enableACME = true;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:8080/";
          index = "index.csp";
          proxyWebsockets = true;
          extraConfig = ''
            # Avoid redirections to the wrong port (ie. 8080)
            proxy_set_header X-Forwarded-Port $server_port;
          '';
        };
      };
    in
    {
      "mmonit.${config.networking.hostName}.${config.domains.main}" = commonConfig;
      "mmonit.${config.domains.main}" = commonConfig;
    };
}
