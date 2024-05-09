{ autoPatchelfHook
, coreutils
, cacert
, curl
, fetchurl
, gawk
, lib
, makeWrapper
, stdenv
, port ? 8080
, mmonitHome ? "/var/lib/mmonit"
}:


stdenv.mkDerivation rec {
  pname = "mmonit";
  version = "4.2.2";

  arch = if stdenv.isAarch64 then "arm64" else "x64";
  checksum =
    if stdenv.isAarch64 then
      "sha256-ZSIWzvTqFetw7WlVSHrP+d8MISObKO791s5MbnkFWHI="
    else
      "sha256-DJUMAplcllqeWGQslRNrkWEh7dFfIbJ0PB5En/t01Mc=";

  src = fetchurl {
    url = "https://mmonit.com/dist/${pname}-${version}-linux-${arch}.tar.gz";
    sha256 = "${checksum}";
  };

  buildInputs = [ autoPatchelfHook makeWrapper ];

  installPhase = ''
    mkdir -p $out
    cp -r ./* $out
    mv $out/db $out/db.og
    ln -sfv ${mmonitHome}/db $out/db

    # M/Monit tries to write to this pidfile on startup
    ln -sfv /var/lib/mmonit/mmonit.pid $out/logs/mmonit.pid

    substituteInPlace $out/upgrade/script/data.sh \
      --replace-fail '/bin/echo' '${coreutils}/bin/echo' \
      --replace-fail 'cp ' '${coreutils}/bin/cp ' \
      --replace-fail 'mv ' '${coreutils}/bin/mv ' \
      --replace-fail 'awk ' '${gawk}/bin/awk'

    # ln -sfv $out/upgrade/upgrade $out/bin/mmonit-upgrade
    cat > $out/bin/mmonit-upgrade <<EOF
    #!/usr/bin/env sh
    export PATH=${lib.makeBinPath [ coreutils gawk ]}

    MMONIT_NEW_HOME=${mmonitHome}/upgrade/mmonit.new
    MMONIT_OLD_HOME=${mmonitHome}/upgrade/mmonit.old
    mkdir -p "\''${MMONIT_OLD_HOME}"
    cp -a "$out" "\''${MMONIT_NEW_HOME}"

    cp -a "${mmonitHome}/db" "${mmonitHome}/db.bak"
    cp -a "${mmonitHome}/db" "\''${MMONIT_OLD_HOME}/db"
    mkdir -p "\''${MMONIT_OLD_HOME}/conf"
    ln -sf "$out/conf/server.xml.orig" "\''${MMONIT_OLD_HOME}/conf/server.xml"
    ln -sf "${mmonitHome}/license.xml" "\''${MMONIT_OLD_HOME}/conf/license.xml"
    if ! "\''${MMONIT_NEW_HOME}/upgrade/upgrade" -d -p "\''${MMONIT_OLD_HOME}"
    then
      echo "Upgrade failed"
      exit 1
    fi
    echo "Upgrade successful"
    cp -a "\''${MMONIT_NEW_HOME}/db/mmonit.db" "${mmonitHome}/db/mmonit.db"
    rm -rf "\''${MMONIT_OLD_HOME}" "\''${MMONIT_NEW_HOME}"
    EOF
    chmod +x $out/bin/mmonit-upgrade

    # mkShellScriptBin
    # makeWrapper $out/upgrade/upgrade $out/bin/mmonit-upgrade \
    #   --prefix PATH : ${lib.makeBinPath [ coreutils gawk ]} \
    #   --run "mkdir -p $MMONIT_OLD_HOME" \
    #   --run "cp -a ${mmonitHome}/db ${mmonitHome}/db.bak" \
    #   --run "cp -a ${mmonitHome}/db $MMONIT_OLD_HOME/db" \
    #   --run "ln -sf ${mmonitHome}/conf/server.xml.orig $MMONIT_OLD_HOME/conf/server.xml" \

    # Patch default server configuration
    # https://mmonit.com/documentation/mmonit_manual.pdf#page=67
    cp $out/conf/server.xml $out/conf/server.xml.orig
    substituteInPlace $out/conf/server.xml \
      --replace-fail 'sqlite:///db/mmonit.db' 'sqlite://${mmonitHome}/db/mmonit.db' \
      --replace-fail 'Logger directory="logs"' 'Logger directory="${mmonitHome}/logs"' \
      --replace-fail '<License file="license.xml"' '<License file="${mmonitHome}/license.xml"' \
      --replace-fail '<Connector address="*" port="8080"' '<Connector address="127.0.0.1" port="${toString port}"' \
      --replace-fail '<CACertificatePath path="/path/to/ca/certs" />' '--><CACertificatePath path="${cacert}/etc/ssl/certs/ca-bundle.crt" /><!--'

    # Create systemd service
    mkdir -p $out/lib/systemd/system

    # Wrapper to handle DB copy and startup
    makeWrapper $out/bin/mmonit $out/bin/mmonit.wrapped \
      --prefix PATH : ${lib.makeBinPath [ curl coreutils ]} \
      --run "mkdir -p ${mmonitHome}/logs" \
      --run "if ! test -f ${mmonitHome}/conf || test -L ${mmonitHome}/conf; then rm -f ${mmonitHome}/conf; ln -sfv $out/conf ${mmonitHome}/conf; fi" \
      --run "if ! test -f ${mmonitHome}/db/mmonit.db; then mkdir -p ${mmonitHome}/db && cp -v $out/db.og/mmonit.db ${mmonitHome}/db/mmonit.db; fi" \
      --run "if ! test -f ${mmonitHome}/license.xml; then test -f /etc/mmonit/license.xml && ln -sfv /etc/mmonit/license.xml ${mmonitHome}/license.xml; fi"

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

    [Install]
    WantedBy=multi-user.target
    EOF
  '';

  meta = {
    homepage = "https://mmonit.com/";
    description = "Easy, proactive monitoring of Unix systems, network and cloud services";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = [ "aarch64-linux" "x86_64-linux" ];
    mainProgram = "mmonit";
  };
}
