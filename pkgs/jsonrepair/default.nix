{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage (finalAttrs: {
  pname = "jsonrepair";
  version = "3.15.0";

  src = fetchFromGitHub {
    owner = "josdejong";
    repo = finalAttrs.pname;
    rev = "v${finalAttrs.version}";
    hash = "sha256-tVqq/wBh1gf4F44DKc5A55E2akpeiMalZUk+8mH1+ZQ=";
  };

  npmDepsHash = "sha256-475pna349LoS+ZorlTNTA/XKZ49Sl3BYSo4h0gg2dTc=";

  # Decouple test-lib vitest suite from npm run build.
  # Upstream's "build" runs "npm-run-all build:**", which picks up "build:validate".
  # Running vitest CLI tests under QEMU user emulation (aarch64) times out.
  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"build:validate":' '"validate":'
  '';

  doCheck = false;

  meta = {
    description = "Repair invalid JSON documents";
    homepage = "https://josdejong.github.io/jsonrepair/";
    license = lib.licenses.isc;
    maintainers = [ lib.maintainers.pschmitt ];
    mainProgram = "jsonrepair";
  };
})
