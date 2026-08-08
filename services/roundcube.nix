{
  config,
  lib,
  pkgs,
  ...
}:
let
  mailHost = "mail.${config.domains.main}";
  dataDir = "/mnt/data/srv/stalwart/roundcube";
  roundcubeUser = "roundcube";
  roundcubeGroup = roundcubeUser;
  roundcubePackage = pkgs.roundcube;
  phpPackage = pkgs.php84.withExtensions (
    {
      enabled,
      all,
    }:
    [
      all.pdo_sqlite
      all.pspell
    ]
    ++ enabled
  );
in
{
  sops.secrets."roundcube/des-key" = config.custom.mkSecret {
    owner = roundcubeUser;
    group = roundcubeGroup;
    mode = "0400";
  };

  users.groups.${roundcubeGroup} = { };
  users.users.${roundcubeUser} = {
    group = roundcubeGroup;
    isSystemUser = true;
    createHome = false;
  };

  environment.etc."roundcube/config.inc.php".text = ''
    <?php

    $config = [];
    $config['db_dsnw'] = 'sqlite:////${dataDir}/db/sqlite.db';
    $config['des_key'] = file_get_contents('${config.sops.secrets."roundcube/des-key".path}');
    $config['log_driver'] = 'syslog';
    $config['max_message_size'] = '25M';
    $config['plugins'] = ['archive', 'zipdownload'];
    $config['mime_types'] = '${pkgs.nginx}/conf/mime.types';
    $config['temp_dir'] = '/tmp/roundcube-temp';
    $config['skin'] = 'elastic';
    $config['request_path'] = '/';
    $config['enable_spellcheck'] = true;
    $config['spellcheck_engine'] = 'pspell';
    $config['spellcheck_languages'] = ['de', 'en', 'fr'];
    $config['imap_host'] = 'tls://${mailHost}:143';
    $config['smtp_host'] = 'tls://${mailHost}:587';
  '';

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${roundcubeUser} ${roundcubeGroup} -"
    "d ${dataDir}/db 0750 ${roundcubeUser} ${roundcubeGroup} -"
    "Z ${dataDir} - ${roundcubeUser} ${roundcubeGroup} - -"
    "d /tmp/roundcube-temp 0750 ${roundcubeUser} ${roundcubeGroup} -"
  ];

  services = {
    phpfpm.pools.roundcube = {
      user = roundcubeUser;
      group = roundcubeGroup;
      phpOptions = ''
        error_log = '/dev/stderr'
        log_errors = on
        post_max_size = 25M
        upload_max_filesize = 25M
      '';
      settings = {
        "listen.owner" = config.services.nginx.user;
        "listen.group" = config.services.nginx.group;
        "listen.mode" = "0660";
        "pm" = "dynamic";
        "pm.max_children" = 20;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 1;
        "pm.max_spare_servers" = 5;
        "pm.max_requests" = 500;
        "catch_workers_output" = true;
      };
      inherit phpPackage;
      phpEnv = {
        ASPELL_CONF = "dict-dir ${
          pkgs.aspellWithDicts (_: [
            pkgs.aspellDicts.de
            pkgs.aspellDicts.en
            pkgs.aspellDicts.fr
          ])
        }/lib/aspell";
      };
    };

    nginx.virtualHosts.${mailHost} = {
      root = "${roundcubePackage}/public_html";
      locations."/" = {
        index = "index.php";
        priority = 1100;
        extraConfig = ''
          add_header Cache-Control 'public, max-age=604800, must-revalidate';
        '';
      };
      locations."~* \\.php(/|$)" = {
        priority = 3130;
        extraConfig = ''
          fastcgi_pass unix:${config.services.phpfpm.pools.roundcube.socket};
          fastcgi_param PATH_INFO $fastcgi_path_info;
          fastcgi_param HTTPS on;
          fastcgi_split_path_info ^(.+\\.php)(/.+)$;
          include ${config.services.nginx.package}/conf/fastcgi.conf;
        '';
      };
      extraConfig = ''
        client_max_body_size 25M;
      '';
    };

    monit.config = lib.mkAfter ''
      check host "roundcube" with address "127.0.0.1"
        group services
        if failed
          port 8443
          protocol https
          with hostheader "${mailHost}"
          request "/"
          with timeout 15 seconds
        for 3 cycles
        then alert
    '';
  };

}
