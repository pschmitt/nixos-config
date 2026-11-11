{ fetchPypi }:
_pythonFinal: pythonPrev:
let
  hatchling131 = pythonPrev.hatchling.overridePythonAttrs (_old: {
    version = "1.31.0";
    src = fetchPypi {
      pname = "hatchling";
      version = "1.31.0";
      hash = "sha256-a0itQGikgu1yObOoIVvFW0eq0zRdWN/JTlU8XS1GIRs=";
    };
  });
in
{
  # mail-parser 4.8 requires hatchling < 1.32, but Nixpkgs supplies 1.32.
  # Use the latest compatible backend only for this package; remove once its
  # declared build requirement permits the selected Hatchling version.
  # Reviewed 2026-11-11 at Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6:
  # the aarch64 build failed its dependency check; x86_64 tests passed.
  mail-parser = pythonPrev.mail-parser.overridePythonAttrs (_old: {
    build-system = [ hatchling131 ];
  });
}
