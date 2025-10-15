{
  lib,
  rustPlatform,
  fetchFromSourcehut,
  stdenv,
  darwin,
}:

rustPlatform.buildRustPackage {
  pname = "davcli";
  version = "0.1.0";

  src = fetchFromSourcehut {
    owner = "~whynothugo";
    repo = "davcli";
    rev = "main";
    hash = "sha256-FEPWykjbJz/ANtxpbzkhNUK+ycfqD2u9scXKmmqcSfs=";
  };

  cargoHash = "sha256-qWKXAqlHy3mD1eoSdxKTbPcBXnnPASuSIxBvcwg9fkA=";

  buildInputs = lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.Security
  ];

  meta = {
    description = "";
    homepage = "https://git.sr.ht/~whynothugo/davcli";
    license = lib.licenses.isc;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "davcli";
  };
}
