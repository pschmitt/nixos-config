{
  config,
  pkgs,
  ...
}:
let
  primaryHost = "mmonit.${config.domains.main}";
  serverAliases = [ "mm.${config.domains.main}" ];

  initScript = pkgs.writeShellScript "mmonit-init" ''
    # Create required runtime directories
    mkdir -p /var/lib/mmonit/logs

    # Initialize database on first run
    if ! test -f /var/lib/mmonit/db/mmonit.db; then
      mkdir -p /var/lib/mmonit/db
      cp ${pkgs.mmonit}/db.og/mmonit.db /var/lib/mmonit/db/mmonit.db
    fi

    # Set up license symlink
    if ! test -e /var/lib/mmonit/license.xml && test -f /etc/mmonit/license.xml; then
      ln -sf /etc/mmonit/license.xml /var/lib/mmonit/license.xml
    fi

    # Keep conf symlink pointing to current package (stale after upgrades)
    ln -sfn ${pkgs.mmonit}/conf /var/lib/mmonit/conf

    # Remove stale PID file — a leftover pid could belong to an unrelated process
    # and cause mmonit to incorrectly report itself as already running
    if test -f /var/lib/mmonit/mmonit.pid; then
      pid=$(cat /var/lib/mmonit/mmonit.pid)
      if ! test -d /proc/"$pid" || ! grep -qF mmonit /proc/"$pid"/cmdline 2>/dev/null; then
        echo "mmonit-init: removing stale PID file (pid $pid is not mmonit)"
        rm -f /var/lib/mmonit/mmonit.pid
      fi
    fi
  '';
in
{
  environment.systemPackages = [ pkgs.mmonit ];

  systemd.services.mmonit = {
    description = "Easy, proactive monitoring of Unix systems, network and cloud services";
    documentation = [ "https://mmonit.com/documentation/" ];
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "mmonit";
      Group = "mmonit";
      StateDirectory = "mmonit";
      StateDirectoryMode = "0700";
      ExecStartPre = "${initScript}";
      ExecStart = "${pkgs.mmonit}/bin/mmonit -i start";
      KillMode = "process";
      Restart = "on-abnormal";
      RestartSec = 30;
    };
  };

  users.users.mmonit = {
    isSystemUser = true;
    home = "/var/lib/mmonit";
    createHome = true;
    group = "mmonit";
  };
  users.groups.mmonit = { };

  # license
  sops.secrets."mmonit/license" = config.custom.mkSecret {
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
      ${primaryHost} = commonConfig // {
        inherit serverAliases;
      };
    };
}
