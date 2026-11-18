{
  lib,
  inputs,
  pkgs,
}:
(import ../../pkgs/termux/nixpp {
  inherit lib inputs pkgs;
}).overrideAttrs
  (_old: {
    pname = "nixpp-runtime-termux";
    version = "0.5.0";
    src = lib.cleanSource ./nixpp;
    cargoDeps = pkgs.rustPlatform.importCargoLock { lockFile = ./nixpp/Cargo.lock; };
    meta = {
      description = "Native Android runtime and declarative guest system manager";
      mainProgram = "nixpp";
      platforms = lib.platforms.linux;
      license = lib.licenses.mit;
    };
  })
