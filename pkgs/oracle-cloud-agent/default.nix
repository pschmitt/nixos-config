{ stdenv
, lib
, rpmextract
, autoPatchelfHook
}:

stdenv.mkDerivation {
  pname = "oracle-cloud-agent";
  version = "1.0.0";

  src =
    if stdenv.isAarch64 then
      ./src/oracle-cloud-agent-1.38.0-7.el9.aarch64.rpm
    else if stdenv.isx86_64 then
      ./src/oracle-cloud-agent-1.38.0-10815.el9.x86_64.rpm
    else
      throw "Unsupported platform";

  buildInputs = [ rpmextract autoPatchelfHook ];

  unpackPhase = ''
    mkdir -p $out
    install -D -m0444 $src $out/oca.rpm
    # NOTE we have to ignore errors here, as cpio tries to set permissions it is not allowed to
    # oracle-cloud-agent> /nix/store/57ciiffh69j5q1l2h6cc7f5rm9n97lms-cpio-2.15/bin/cpio: ./var/log/oracle-cloud-agent/plugins/osms: Cannot change mode to rwxrwsr-x: Operation not permitted
    pushd $out
    rpmextract $out/oca.rpm || true
    rm $out/oca.rpm
  '';

  patchPhase = ''
    # FIXME None of these shebang fixes seems to work
    # mapfile -t SCRIPTS < <(find $out -type f -exec grep -IlE "^#!/" {} \;)
    # patchShebangs "''${SCRIPTS[@]}"
    # patchShebangs --host $out/usr/bin/ocatools/diagnostic \
    #   $out/usr/libexec/oracle-cloud-agent/plugins/oci-jms/oci-jms \
    #   $out/usr/sbin/osms

    mapfile -t FILES < <(find $out -type f -exec grep -Il /usr/libexec {} \;)
    substituteInPlace "''${FILES[@]}" \
      --replace-fail '/usr/libexec' "$out/usr/libexec"
  '';

  postInstall = ''
    # mkdir -p $out/lib
    # mv $out/etc/systemd $out/lib/systemd
    install -D -m0444 -t $out/lib/systemd/system $out/etc/systemd/system/oracle-cloud-agent.service
    # /var contains a whole directory structure, but no files
    # /usr/lib holds usr/lib/python3.9/site-packages/dnf-plugins/osmsplugin.py
    rm -rf $out/var $out/etc/systemd $out/etc/yum $out/usr/lib
  '';

  meta = with lib; {
    description = "Oracle Cloud Agent";
    homepage = "https://www.oracle.com/cloud/";
    license = licenses.upl;
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
