_pyfinal: pyprev: {
  # Python 3.13 tests fail: pysaml2 7.5.4 paths outside the schema sandbox
  # are rejected by xmlschema 4. [Upstream PR #1044](https://github.com/IdentityPython/pysaml2/pull/1044)
  # fixes this. Reviewed 2026-11-06 at Nixpkgs
  # b1b875982b17dabde9b4a37f3e229e74913e6db3; remove when it lands.
  pysaml2 = pyprev.pysaml2.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./pysaml2-xmlschema4.patch ];
  });
}
