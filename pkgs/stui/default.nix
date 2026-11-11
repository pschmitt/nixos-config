{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  sqlite,
}:

rustPlatform.buildRustPackage rec {
  pname = "stui";
  version = "0.11.1";

  src = fetchFromGitHub {
    owner = "corcoran";
    repo = "stui";
    rev = "v${version}";
    hash = "sha256-bprPYW5gDBgrKQFb9uRPIL5X+zmIeL/A+PbJPkt6EHk=";
  };

  # Upstream lock with security updates for selected transitive dependencies.
  # Ratatui 0.29 pins lru 0.12 (GHSA-rhfx-m35p-ff5j); its layout cache uses
  # get_or_insert/resize, not the affected IterMut. Recheck on a Stui bump.
  cargoLock.lockFile = ./Cargo.lock;
  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
  '';

  # Nixpkgs links rusqlite against system SQLite even with the bundled feature.
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ sqlite ];

  meta = {
    description = "Syncthing TUI for file and folder management";
    homepage = "https://github.com/corcoran/stui";
    # Upstream ships no LICENSE file as of v0.11.1.
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "stui";
  };
}
