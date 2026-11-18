{
  lib,
  rustPlatform,
  python3,
}:
rustPlatform.buildRustPackage {
  pname = "nixpp";
  version = "0.5.0";
  src = lib.cleanSource ./nixpp;
  cargoLock.lockFile = ./nixpp/Cargo.lock;
  NIXPP_REFERENCE_PREPARE = ./system/prepare-session.py;
  NIXPP_REFERENCE_PYTHON = "${python3}/bin/python3";

  meta = {
    description = "Declarative Android guest system manager";
    mainProgram = "nixpp";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
  };
}
