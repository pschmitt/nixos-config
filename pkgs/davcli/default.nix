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
  rev = "90e0e8da68eaf6ca3747f48a6d1bdf597e837af7";

  src = fetchFromSourcehut {
    owner = "~whynothugo";
    repo = "davcli";
    inherit rev;
    hash = "sha256-skGNDmEACmMSep685JfVM2uJqOpxEaeDi5LwiL02jBw=";
  };

  cargoHash = "sha256-/bp/Zs16oe2879NeWKVSmPdbLO+IERaZ8lL6Ov6EAT4=";

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
