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
  rev = "6a11363464c5d59ff52b42a389fa233f6f8a3e3f";

  src = fetchFromSourcehut {
    owner = "~whynothugo";
    repo = "davcli";
    inherit rev;
    hash = "sha256-TkgD0WdQlGONP5pU2NYy8KzVSmT71A4pDDabrmJbub0=";
  };

  cargoHash = "sha256-wosrU2/FmwoPFiBFm96RRadGj4U6rmvokm3JrnV7v5M=";

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
