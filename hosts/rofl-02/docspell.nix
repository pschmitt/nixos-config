{
  config,
  inputs,
  pkgs,
  ...
}:
let
  hostnames = [ "docspell.${config.networking.hostName}.${config.custom.mainDomain}" ];
in
{
  # https://docspell.org/docs/install/nix/

  # joex: job executor
  services.docspell-joex = {
    enable = true;
    package = inputs.docspell.packages.${pkgs.system}.docspell-joex;
    base-url = "http://localhost:7878";
    bind = {
      address = "127.0.0.1";
      port = 7878;
    };
    scheduler = {
      pool-size = 1;
    };
    jdbc = {
      # FIXME docspll does NOT support UNIX sockets!
      # url = "jdbc:postgresql://localhost:5432/docspell";
      url = "jdbc:postgresql://%2Fvar%2Frun%2Fpostgresql/docspell";
      user = "docspell";
      password = "";
    };
  };

  services.docspell-restserver = {
    enable = true;
    package = inputs.docspell.packages.${pkgs.system}.docspell-restserver;
    base-url = "http://localhost:7880";
    bind = {
      address = "127.0.0.1";
      port = 7880;
    };
    auth = {
      server-secret = "b64:EirgaudMyNvWg4TvxVGxTu-fgtrto4ETz--Hk9Pv2o4=";
    };
    backend = {
      signup = {
        mode = "invite";
        new-invite-password = "dsinvite2";
        invite-time = "30 days";
      };
      jdbc = {
        # FIXME docspll does NOT support UNIX sockets!
        # url = "jdbc:postgresql://localhost:5432/docspell";
        url = "jdbc:postgresql://%2Fvar%2Frun%2Fpostgresql/docspell";
        user = "docspell";
        password = "";
      };
    };
  };

  # install postgresql and initially create user/database
  # services.postgresql =
  #   let
  #     pginit = pkgs.writeText "pginit.sql" ''
  #       CREATE USER docspell WITH PASSWORD 'docspell' LOGIN CREATEDB;
  #       GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO docspell;
  #       GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO docspell;
  #       CREATE DATABASE DOCSPELL OWNER 'docspell';
  #     '';
  #   in
  #   {
  #     enable = true;
  #     # package = pkgs.postgresql_11;
  #     enableTCPIP = true;
  #     initialScript = pginit;
  #     port = 5432;
  #     authentication = ''
  #       host  all  all 0.0.0.0/0 md5
  #     '';
  #   };

  services.postgresql = {
    enable = true;
    # package = pkgs.postgresql_15;
    # enableTCPIP = true;
    ensureDatabases = [ "docspell" ];
    ensureUsers = [
      {
        name = "docspell";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
  };

  services.nginx =
    let
      virtualHosts = builtins.listToAttrs (
        map (hostname: {
          name = hostname;
          value = {
            enableACME = true;
            # FIXME https://github.com/NixOS/nixpkgs/issues/210807
            acmeRoot = null;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://${config.services.docspell-restserver.bind.address}:${toString config.services.docspell-restserver.bind.port}";
              proxyWebsockets = true;
              recommendedProxySettings = true;
            };
          };
        }) hostnames
      );
    in
    {
      virtualHosts = virtualHosts;
    };
}
