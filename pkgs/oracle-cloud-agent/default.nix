{ stdenv, lib, rpm, rpmextract, cpio }:

stdenv.mkDerivation {
  pname = "oracle-cloud-agent";
  version = "1.0.0";

  # rpm_x86_64 = ./oracle-cloud-agent-1.38.0-10815.el9.x86_64.rpm;
  # rpm_aarch64 = ./oracle-cloud-agent-1.38.0-7.el9.aarch64.rpm;

  src =
    if stdenv.isAarch64 then
      ./oracle-cloud-agent-1.38.0-7.el9.aarch64.rpm
    else if stdenv.isx86_64 then
      ./oracle-cloud-agent-1.38.0-10815.el9.x86_64.rpm
    else
      throw "Unsupported platform";

  buildInputs = [ rpm rpmextract cpio ];

  unpackPhase = ''
    mkdir -p $out
    mv $src $out/file
    rpmextract $out/file
    # rpm2cpio $src | cpio -idm --no-preserve-owner
  '';

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp -r * $out/
  '';

  meta = with lib; {
    description = "Oracle Cloud Agent";
    homepage = "https://www.oracle.com/cloud/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
