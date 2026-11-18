{
  lib,
  rustPlatform,
  python3,
}:
rustPlatform.buildRustPackage {
  pname = "nixpp";
  version = "0.5.0";
  src = lib.cleanSource ./source;
  cargoLock.lockFile = ./source/Cargo.lock;
  NIXPP_REFERENCE_PREPARE = ./tests/prepare-session.py;
  NIXPP_REFERENCE_PYTHON = "${python3}/bin/python3";

  meta = {
    description = "Declarative Android guest system manager";
    mainProgram = "nixpp";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
  };
}
