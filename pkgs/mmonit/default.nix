{ autoPatchelfHook
, coreutils
, cacert
, curl
, fetchurl
, lib
, makeWrapper
, stdenv
, port ? 8080
, mmonitHome ? "/var/lib/mmonit"
}:

stdenv.mkDerivation rec {
  pname = "mmonit";
  version = "4.2.1";

  arch = if stdenv.isAarch64 then "arm64" else "x64";
  checksum =
    if stdenv.isAarch64 then
      "sha256-InB7zaUiFJj4kbuKOcJ/AQBhrYzSAmhanP7/f3OpH7A="
    else
      "sha256-aKJBEgENTXZ6cRfoAMjFY7w+BDHRHEMC1rTyRvAT+Fw=";

  src = fetchurl {
    url = "https://mmonit.com/dist/${pname}-${version}-linux-${arch}.tar.gz";
    sha256 = "${checksum}";
  };

  buildInputs = [ autoPatchelfHook makeWrapper ];

  installPhase = ''
    mkdir -p $out
    cp -r ./* $out

    ln -sfv $out/upgrade/upgrade $out/bin/mmonit-upgrade
    # M/Monit tries to write to this pidfile on startup
    ln -sfv /var/lib/mmonit/mmonit.pid $out/logs/mmonit.pid

    # FIXME Disabling these 2 settings is an ugly hack and also does not fix the
    # M/Monit license fetching issue at startup
    # --replace-fail 'SelfSignedCertificate allow="false"' 'SelfSignedCertificate allow="true"' \
    # --replace-fail '<HostnameVerification enable="true"' '<HostnameVerification enable="false"'
    substituteInPlace $out/conf/server.xml \
      --replace-fail 'sqlite:///db/mmonit.db' 'sqlite://${mmonitHome}/db/mmonit.db' \
      --replace-fail 'Logger directory="logs"' 'Logger directory="${mmonitHome}/logs"' \
      --replace-fail '<License file="license.xml"' '<License file="${mmonitHome}/license.xml"' \
      --replace-fail '<Connector address="*" port="8080"' '<Connector address="127.0.0.1" port="${toString port}"'

    # Create systemd service
    mkdir -p $out/lib/systemd/system

    # Wrapper to handle DB copy and startup
    # FIXME The license.xml retrieval should be handled by mmonit directly,
    # but it fails with:
    # IOException: SSL connect error [88.99.240.67] error:0A000086:SSL routines::certificate verify failed
    #
    # The following does not seem to work:
    # --set SSL_CERT_FILE "''${cacert}/etc/ssl/certs/ca-bundle.crt" \
    # --set OPENSSLDIR "''${cacert}/etc/ssl" \
    #
    # This workaround allows M/Monit to start but does not fix the underlying
    # issue
    # --run "test -f /var/lib/mmonit/license.xml || curl -fsSL -X POST https://mmonit.com/api/services/license/trial -o /var/lib/mmonit/license.xml"
    makeWrapper $out/bin/mmonit $out/bin/mmonit.wrapped \
      --prefix PATH : ${lib.makeBinPath [ curl coreutils ]} \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --run "mkdir -p /var/lib/mmonit/logs" \
      --run "if ! test -f ${mmonitHome}/conf || test -L ${mmonitHome}/conf; then rm -f ${mmonitHome}/conf; ln -sfv $out/conf ${mmonitHome}/conf; fi" \
      --run "if ! test -f ${mmonitHome}/db/mmonit.db; then mkdir -p ${mmonitHome}/db && cp -v $out/db/mmonit.db ${mmonitHome}/db/mmonit.db; fi" \
      --run "if ! test -f ${mmonitHome}/license.xml; then test -f /etc/mmonit/license.xml && ln -sfv /etc/mmonit/license.xml ${mmonitHome}/license.xml; fi" \
      --run "test -f ${mmonitHome}/license.xml || curl -fsSL -X POST https://mmonit.com/api/services/license/trial -o ${mmonitHome}/license.xml"

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
