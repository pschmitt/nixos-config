{
  lib,
  rustPlatform,
  fetchFromGitHub,
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

  cargoLock.lockFile = "${src}/Cargo.lock";

  # rusqlite's "bundled" feature vendors and compiles its own SQLite, and
  # reqwest is configured for rustls (not openssl) -- no extra system
  # buildInputs needed.

  meta = {
    description = "Syncthing TUI for file and folder management";
    homepage = "https://github.com/corcoran/stui";
    # Upstream ships no LICENSE file as of v0.11.1.
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "stui";
  };
}
