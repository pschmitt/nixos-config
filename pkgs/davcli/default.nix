{
  lib,
  rustPlatform,
  fetchgit,
  stdenv,
  darwin,
  nix-update-script,
}:

rustPlatform.buildRustPackage rec {
  pname = "davcli";
  version = "unstable-${lib.strings.substring 0 10 rev}";
  rev = "1019b79b7c0418202709e9dc717720a0e1d5cc0c";

  src = fetchgit {
    url = "https://git.sr.ht/~whynothugo/davcli";
    inherit rev;
    fetchSubmodules = true;
    hash = "sha256-wHwvXqiELzGFDIu757sZSadguNd2EUvjGPpxEbczm5I=";
  };

  cargoHash = "sha256-ZmV53NEM8Mz42Mss79Nq3YI40bx5TIng/dCYrV5gEfQ=";

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
      "--version-regex"
      "(?:0-)?(unstable-[0-9]{4}-[0-9]{2}-[0-9]{2})"
    ];
  };

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [
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
