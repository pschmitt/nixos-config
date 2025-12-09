{
  lib,
  stdenv,
  dpkg,
  autoPatchelfHook,
  zlib,
  openssl,
  libnl,
  inputs,
  callPackage,
  ...
}:

let
  unwrapped = stdenv.mkDerivation {
    pname = "falcon-sensor-unwrapped";
    version = "7.29.0-18202";
    src = ../../falcon-sensor_7.29.0-18202_amd64.deb;

    nativeBuildInputs = [
      dpkg
      autoPatchelfHook
    ];
    buildInputs = [
      zlib
      openssl
      libnl
    ];

    sourceRoot = ".";
    unpackCmd = "dpkg-deb -x $src .";

    installPhase = "cp -r ./ $out/";

    meta = with lib; {
      description = "Crowdstrike Falcon Sensor";
      license = licenses.unfree;
      platforms = platforms.linux;
    };
  };

  wrapped = callPackage (inputs.falcon-sensor.outPath + "/falcon-sensor.nix") {
    falcon-sensor-unwrapped = unwrapped;
  };
in
wrapped.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit unwrapped;
  };
})
