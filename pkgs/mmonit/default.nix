{
  autoPatchelfHook,
  coreutils,
  cacert,
  fetchurl,
  gawk,
  gnused,
  lib,
  stdenv,
  systemd,
  port ? 8080,
  mmonitHome ? "/var/lib/mmonit",
  user ? "mmonit",
  sessionTimeout ? "43200 min", # 30days, default is 30min
}:

stdenv.mkDerivation rec {
  pname = "mmonit";
  version = "4.3.3";

  arch = if stdenv.isAarch64 then "arm64" else "x64";
  checksum =
    if stdenv.isAarch64 then
      "sha256-fqTHo60tsi9cL+WGVA0FAwkJaAJRf6EKVcwaMmf1okU="
    else
      "sha256-giRzg0sjp6pVr/cB1K0lT5RU13Ksihz2kYHci9jFo7Q=";

  src = fetchurl {
    # NOTE Only the latest release seems to be available at this url
    # url = "https://mmonit.com/dist/${pname}-${version}-linux-${arch}.tar.gz";
    url = "https://mmonit.com/dist/4/${version}/${pname}-${version}-linux-${arch}.tar.gz";
    hash = "${checksum}";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    mkdir -p $out
    cp -r ./* $out
    mv $out/db $out/db.og
    ln -sfv ${mmonitHome}/db $out/db

    # Redirect PID file to writable location (nix store is read-only)
    ln -sfv ${mmonitHome}/mmonit.pid $out/logs/mmonit.pid

    # Patch default server configuration
    # https://mmonit.com/documentation/mmonit_manual.pdf#page=67
    substituteInPlace $out/conf/server.xml \
      --replace-fail 'sqlite:///db/mmonit.db' 'sqlite://${mmonitHome}/db/mmonit.db' \
      --replace-fail 'Logger directory="logs"' 'Logger directory="${mmonitHome}/logs"' \
      --replace-fail '<License file="license.xml"' '<License file="${mmonitHome}/license.xml"' \
      --replace-fail '<Connector address="*" port="8080"' '<Connector address="127.0.0.1" port="${toString port}"' \
      --replace-fail '<CACertificatePath path="/path/to/ca/certs" />' '--><CACertificatePath path="${cacert}/etc/ssl/certs/ca-bundle.crt" /><!--' \
      --replace-fail '<Context path="" docBase="docroot" sessionTimeout="30 min"' '<Context path="" docBase="docroot" sessionTimeout="${sessionTimeout}"'

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
