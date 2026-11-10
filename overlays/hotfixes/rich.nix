{ lib }:
_pythonFinal: pythonPrev:
lib.optionalAttrs (lib.versionAtLeast pythonPrev.python.version "3.14") {
  # Rich 15.0.0's test writes less than Python 3.14's stdout buffer, so piping
  # its demo to `head -1` never exercises Rich's synchronous BrokenPipeError
  # handler. Reviewed 2026-11-10 on Nixpkgs
  # f4a03c008967841f2a0b3cb7c436fc6fc31671f6; this is the only failing test
  # (955 pass, 25 skip), and the package otherwise builds.
  # No upstream fix is recorded. Remove once the test forces a write after the
  # pipe closes or otherwise passes under Python 3.14.
  rich = pythonPrev.rich.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [ "test_brokenpipeerror" ];
  });
}
