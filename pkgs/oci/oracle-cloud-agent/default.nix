{
  autoPatchelfHook,
  coreutils,
  fetchurl,
  gawk,
  lib,
  rpmextract,
  stdenv,
  zlib,
}:

stdenv.mkDerivation rec {
  pname = "oracle-cloud-agent";
  # Version metadata is tracked in ./sources.json to keep the updater simple.
  # The update script rewrites that file; default.nix just reads it.
  inherit (builtins.fromJSON (builtins.readFile ./sources.json))
    version
    release
    hashAarch64
    hashX86_64
    ;

  # NOTE the Oracle Cloud Agent is available from the Oracle Linux yum repo
  # But this is not a public repo, so we have to download the RPMs manually
  # To get the URLs you can run $ yumdownloader --urls oracle-cloud-agent
  # from an OCI machine where the Oracle Linux yum repo is configured
  # Building this package directly on an OCI machine should work out of the box
  # Addendum: there's wrapper next to this file (./get-download-urls.sh) that
  # should output the URLs
  # yum_repo = "oci-yum.brkn.lol"; # proxy to the Oracle Linux yum repo
  yum_repo = "yum.eu-frankfurt-1.oci.oraclecloud.com";
  src = fetchurl {
    url =
      if stdenv.isAarch64 then
        "https://${yum_repo}/repo/OracleLinux/OL9/oci/included/aarch64/getPackage/oracle-cloud-agent-${version}-${release}.aarch64.rpm"
      else if stdenv.isx86_64 then
        "https://${yum_repo}/repo/OracleLinux/OL9/oci/included/x86_64/getPackage/oracle-cloud-agent-${version}-${release}.x86_64.rpm"
      else
        throw "Unsupported platform";
    hash =
      if stdenv.isAarch64 then
        hashAarch64
      else if stdenv.isx86_64 then
        hashX86_64
      else
        throw "Unsupported platform";
  };
  # Manually downloaded RPMs
  # src =
  #   if stdenv.isAarch64 then
  #     ./src/oracle-cloud-agent-1.38.0-7.el9.aarch64.rpm
  #   else if stdenv.isx86_64 then
  #     ./src/oracle-cloud-agent-1.38.0-10815.el9.x86_64.rpm
  #   else
  #     throw "Unsupported platform";

  passthru.updateScript = ./update.sh;

  buildInputs = [
    autoPatchelfHook
    gawk
    rpmextract
    zlib
  ];

  unpackPhase = ''
    mkdir -p $out
    pushd $out
    install -D -m0444 $src $out/oca.rpm
    # NOTE we have to ignore errors here, as cpio tries to set permissions it is not allowed to
    # oracle-cloud-agent> /nix/store/57ciiffh69j5q1l2h6cc7f5rm9n97lms-cpio-2.15/bin/cpio: ./var/log/oracle-cloud-agent/plugins/osms: Cannot change mode to rwxrwsr-x: Operation not permitted
    rpmextract $out/oca.rpm || true
    rm $out/oca.rpm
  '';

  patchPhase = ''
    # FIXME None of these shebang fixes seems to work
    # mapfile -t SCRIPTS < <(find $out -type f -exec grep -IlE "^#!/" {} \;)
    # patchShebangs "''${SCRIPTS[@]}"
    # patchShebangs $out/usr/bin/ocatools/diagnostic \
    #   $out/usr/libexec/oracle-cloud-agent/plugins/oci-jms/oci-jms \
    #   $out/usr/sbin/osms

    mapfile -t FILES < <(find $out -type f -exec grep -Il /usr/libexec {} \;)
    substituteInPlace "''${FILES[@]}" \
      --replace-fail '/usr/libexec' "$out/usr/libexec"

    sed -i '/^ExecStart=/i ExecStartPre=${coreutils}/bin/mkdir -p /var/lib/oracle-cloud-agent/tmp' \
      $out/etc/systemd/system/oracle-cloud-agent.service
  '';

  postInstall = ''
    install -D -m0444 -t $out/lib/systemd/system \
      $out/etc/systemd/system/oracle-cloud-agent.service
    # /var contains a whole directory structure, but no files
    # /usr/lib holds usr/lib/python3.9/site-packages/dnf-plugins/osmsplugin.py
    rm -rf $out/var $out/etc/systemd $out/etc/yum $out/usr/lib
  '';

  meta = with lib; {
    description = "Oracle Cloud Agent";
    homepage = "https://docs.cloud.oracle.com/iaas/";
    license = licenses.upl;
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
