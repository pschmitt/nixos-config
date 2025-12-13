{
  lib,
  rustPlatform,
  fetchFromSourcehut,
  stdenv,
  darwin,
  nix-update-script,
}:

rustPlatform.buildRustPackage rec {
  pname = "davcli";
  version = "unstable-${lib.strings.substring 0 10 rev}";
  rev = "1dd3673ef82660e6c15640dbcd517889cb691277";

  src = fetchFromSourcehut {
    owner = "~whynothugo";
    repo = "davcli";
    inherit rev;
    hash = "sha256-FEPWykjbJz/ANtxpbzkhNUK+ycfqD2u9scXKmmqcSfs=";
  };

  cargoHash = "sha256-qWKXAqlHy3mD1eoSdxKTbPcBXnnPASuSIxBvcwg9fkA=";

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
      "--version-regex"
      "(?:0-)?(unstable-[0-9]{4}-[0-9]{2}-[0-9]{2})"
    ];
  };

  buildInputs = lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.Security
  ];

  meta = {
    description = "Command line CalDav and CardDav client";
    homepage = "https://git.sr.ht/~whynothugo/davcli";
    license = lib.licenses.isc;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "davcli";
  };
}
