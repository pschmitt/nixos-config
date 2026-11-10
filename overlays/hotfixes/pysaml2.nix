_pyfinal: pyprev: {
  # Python 3.13 tests fail: pysaml2 7.5.4 paths outside the schema sandbox
  # are rejected by xmlschema 4. [Upstream PR #1044](https://github.com/IdentityPython/pysaml2/pull/1044)
  # fixes this. Reviewed 2026-11-10 at Nixpkgs
  # f4a03c008967841f2a0b3cb7c436fc6fc31671f6; without this patch, 42 tests
  # fail and the patched package builds successfully. Remove when PR #1044
  # reaches the pinned source.
  pysaml2 = pyprev.pysaml2.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./pysaml2-xmlschema4.patch ];
  });
}
