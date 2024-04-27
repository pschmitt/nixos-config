{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, coreutils
, curl
, cacert
, makeWrapper
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

  buildInputs = [ autoPatchelfHook makeWrapper cacert ];

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
      --replace-fail 'sqlite:///db/mmonit.db' 'sqlite:///var/lib/mmonit/mmonit.db' \
      --replace-fail 'Logger directory="logs"' 'Logger directory="/var/lib/mmonit/logs"' \
      --replace-fail '<License file="license.xml"' '<License file="/var/lib/mmonit/license.xml"'

    # Create systemd service
    mkdir -p $out/lib/systemd/system

    # Wrapper to handle DB copy and startup
    # FIXME The license.xml retrieval should be handled by mmonit directly,
    # but it fails with:
    # IOException: SSL connect error [88.99.240.67] error:0A000086:SSL routines::certificate verify failed
    #
    # The following does not seem to work:
    # --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
    # --set OPENSSLDIR "${cacert}/etc/ssl" \
    #
    # This workaround allows M/Monit to start but does not fix the underlying
    # issue
    # --run "test -f /var/lib/mmonit/license.xml || curl -fsSL -X POST https://mmonit.com/api/services/license/trial -o /var/lib/mmonit/license.xml"
    makeWrapper $out/bin/mmonit $out/bin/mmonit.wrapped \
      --prefix PATH : ${lib.makeBinPath [ curl coreutils ]} \
      --add-flags "-i" \
      --run "mkdir -p /var/lib/mmonit/logs" \
      --run "test -f /var/lib/mmonit/mmonit.db || cp -v $out/db/mmonit.db /var/lib/mmonit/mmonit.db" \
      --run "test -f /var/lib/mmonit/license.xml || curl -fsSL -X POST https://mmonit.com/api/services/license/trial -o /var/lib/mmonit/license.xml"

    # Systemd service
    cat > $out/lib/systemd/system/mmonit.service <<EOF
    [Unit]
    Description=M/Monit service
    After=network.target

    [Service]
    Type=simple
    ExecStart=$out/bin/mmonit.wrapped
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOF
  '';

  meta = {
    homepage = "https://mmonit.com/";
    description = "Monitoring system";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = [ "aarch64-linux" "x86_64-linux" ];
    mainProgram = "mmonit";
  };
}
