{
  fetchFromGitHub,
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "iris-viewer";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "sadlavaarsc";
    repo = "iris";
    rev = "v${finalAttrs.version}";
    hash = "sha256-o6sIRQCizZkaLSs/c2Q9Fgc4MWxka34QVvgzhJ+jI1w=";
  };

  cargoLock.lockFile = ./Cargo.lock;
  prePatch = ''
    cp ${./Cargo.lock} Cargo.lock
  '';

  meta = {
    description = "Terminal image viewer with Kitty graphics support and protocol fallback";
    homepage = "https://github.com/sadlavaarsc/iris";
    license = lib.licenses.mit;
    mainProgram = "iris";
    platforms = lib.platforms.unix;
  };
})
