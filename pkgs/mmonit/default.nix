{
  autoPatchelfHook,
  coreutils,
  cacert,
  curl,
  fetchurl,
  gawk,
  gnused,
  lib,
  makeWrapper,
  stdenv,
  systemd,
  port ? 8080,
  mmonitHome ? "/var/lib/mmonit",
  user ? "root", # TODO run as a dedicated user
}:

stdenv.mkDerivation rec {
  pname = "mmonit";
  version = "4.3.1";

  arch = if stdenv.isAarch64 then "arm64" else "x64";
  checksum =
    if stdenv.isAarch64 then
      "sha256-t7fkAJ1DRbwteATEG7G7SzljOySlClRycxdfUU7B6aY="
    else
      "sha256-viq87tKQ0AVvTi3MVPOB0ILzpBCTCy2HIvJ5cXA6WQA=";

  src = fetchurl {
    url = "https://mmonit.com/dist/${pname}-${version}-linux-${arch}.tar.gz";
    hash = "${checksum}";
  };

  buildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  installPhase = ''
    mkdir -p $out
    cp -r ./* $out
    mv $out/db $out/db.og
    ln -sfv ${mmonitHome}/db $out/db

    # M/Monit tries to write to this pidfile on startup
    ln -sfv /var/lib/mmonit/mmonit.pid $out/logs/mmonit.pid

    # Patch default server configuration
    # https://mmonit.com/documentation/mmonit_manual.pdf#page=67
    substituteInPlace $out/conf/server.xml \
      --replace-fail 'sqlite:///db/mmonit.db' 'sqlite://${mmonitHome}/db/mmonit.db' \
      --replace-fail 'Logger directory="logs"' 'Logger directory="${mmonitHome}/logs"' \
      --replace-fail '<License file="license.xml"' '<License file="${mmonitHome}/license.xml"' \
      --replace-fail '<Connector address="*" port="8080"' '<Connector address="127.0.0.1" port="${toString port}"' \
      --replace-fail '<CACertificatePath path="/path/to/ca/certs" />' '--><CACertificatePath path="${cacert}/etc/ssl/certs/ca-bundle.crt" /><!--'

    # Create systemd service
    mkdir -p $out/lib/systemd/system

    # Wrapper to handle DB initial copy and license
    makeWrapper $out/bin/mmonit $out/bin/mmonit.wrapped \
      --prefix PATH : ${
        lib.makeBinPath [
          curl
          coreutils
        ]
      } \
      --run "mkdir -p ${mmonitHome}/logs" \
      --run "if ! test -f ${mmonitHome}/conf || test -L ${mmonitHome}/conf; then rm -f ${mmonitHome}/conf; ln -sfv $out/conf ${mmonitHome}/conf; fi" \
      --run "if ! test -f ${mmonitHome}/db/mmonit.db; then mkdir -p ${mmonitHome}/db && cp -v $out/db.og/mmonit.db ${mmonitHome}/db/mmonit.db; fi" \
      --run "if ! test -f ${mmonitHome}/license.xml; then test -f /etc/mmonit/license.xml && ln -sfv /etc/mmonit/license.xml ${mmonitHome}/license.xml; fi"

    # M/Monitor upgrade script
    substituteInPlace $out/upgrade/script/data.sh \
      --replace-fail '/bin/echo' '${coreutils}/bin/echo' \
      --replace-fail 'cp ' '${coreutils}/bin/cp ' \
      --replace-fail 'mv ' '${coreutils}/bin/mv ' \
      --replace-fail 'awk ' '${gawk}/bin/awk'

    cat > $out/bin/mmonit-upgrade <<EOF
    #!/usr/bin/env sh
    export PATH=${
      lib.makeBinPath [
        coreutils
        gawk
        gnused
        systemd
      ]
    }

    if systemctl is-active -q mmonit.service >/dev/null 2>&1
    then
      SERVICE_IS_ACTIVE=1
      systemctl stop mmonit.service
    fi

    MMONIT_NEW_HOME="${mmonitHome}/upgrade/mmonit.new"
    MMONIT_OLD_HOME="${mmonitHome}/upgrade/mmonit.old"
    DB_BACKUP_DIR="${mmonitHome}/upgrade/backups/db-${version}"

    # populate the new install dir
    rm -rf "\''${MMONIT_NEW_HOME}"
    cp -a "$out" "\''${MMONIT_NEW_HOME}"
    trap 'rm -rf "\''${MMONIT_NEW_HOME}" "\''${MMONIT_OLD_HOME}"' EXIT

    mkdir -p "\''${MMONIT_OLD_HOME}/db" "\''${MMONIT_OLD_HOME}/conf" \
      "\''${DB_BACKUP_DIR}"

    # backup db
    cp -vaL "${mmonitHome}"/db/mmonit.* "\''${DB_BACKUP_DIR}"
    echo "Backed up db to \''${DB_BACKUP_DIR}"

    # copy database files to old install dir
    cp -vaL "${mmonitHome}"/db/mmonit.* "\''${MMONIT_OLD_HOME}/db"

    # Update config to target local db file
    sed 's#sqlite://${mmonitHome}/db/mmonit.db#sqlite:///db/mmonit.db#g' \
      $out/conf/server.xml > "\''${MMONIT_OLD_HOME}/conf/server.xml"
    ln -sfv "${mmonitHome}/license.xml" "\''${MMONIT_OLD_HOME}/conf/license.xml"

    if ! "\''${MMONIT_NEW_HOME}/upgrade/upgrade" -d -p "\''${MMONIT_OLD_HOME}"
    then
      echo "Upgrade failed"
      exit 1
    fi

    echo "Upgrade successful"

    if [[ -n "$SERVICE_IS_ACTIVE" ]]
    then
      systemctl start mmonit.service
    fi
    EOF
    chmod +x $out/bin/mmonit-upgrade

    # systemd service - https://mmonit.com/wiki/MMonit/Setup
    cat > $out/lib/systemd/system/mmonit.service <<EOF
    [Unit]
    Description = Easy, proactive monitoring of Unix systems, network and cloud services
    Documentation= https://mmonit.com/documentation/
    After=network.target

    [Service]
    Type=simple
    KillMode=process
    ExecStart=$out/bin/mmonit.wrapped start -i
    ExecStop=$out/bin/mmonit.wrapped stop
    PIDFile=/var/lib/mmonit/logs/mmonit.pid
    Restart=on-abnormal
    RestartSec=30
    User=${user}

    [Install]
    WantedBy=multi-user.target
    EOF
  '';

  meta = {
    homepage = "https://mmonit.com/";
    description = "Easy, proactive monitoring of Unix systems, network and cloud services";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    mainProgram = "mmonit";
  };
}
