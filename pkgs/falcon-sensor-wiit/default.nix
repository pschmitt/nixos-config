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
  requireFile,
  ...
}:

let
  source = {
    name = "falcon-sensor_7.29.0-18202_amd64.deb";
    url = "https://blobs.brkn.lol/private/crowdstrike-falcon/falcon-sensor_7.29.0-18202_amd64.deb";
    sha256 = "sha256-aTN4ca1C1L7wxjeOoEAPjuTWhew4V4oUhmg0yxBA2SY=";
  };

  unwrapped = stdenv.mkDerivation {
    pname = "falcon-sensor-unwrapped";
    version = "7.29.0-18202";
    src = requireFile source;

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
    # NOTE: This is required for us to be able to get the urls set programatically in the fetch-garbage script
    proprietarySource = source;
  };
})
