{
  lib,
  inputs,
  pkgs,
}:
let
  seed = import ./bootstrap-seed.nix { inherit lib pkgs inputs; };
in
(import ./legacy.nix {
  inherit lib inputs pkgs;
}).overrideAttrs
  (old: {
    pname = "nixpp-runtime-termux";
    version = "0.5.0";
    src = lib.cleanSource ./source;
    cargoDeps = pkgs.rustPlatform.importCargoLock { lockFile = ./source/Cargo.lock; };
    # Pin the seed shipped next to this executable; nixpp refuses any other.
    preBuild = (old.preBuild or "") + ''
      NIXPP_BOOTSTRAP_SHA256=$(sha256sum ${seed}/share/nixpp/bootstrap-aarch64.zip | cut -d' ' -f1)
      export NIXPP_BOOTSTRAP_SHA256
    '';
    passthru = old.passthru // {
      inherit seed;
    };
    meta = {
      description = "Native Android runtime and declarative guest system manager";
      mainProgram = "nixpp";
      platforms = lib.platforms.linux;
      license = lib.licenses.mit;
    };
  })
