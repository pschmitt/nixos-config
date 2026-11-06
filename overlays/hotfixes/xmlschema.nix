_pyfinal: pyprev: {
  # xmlschema 4.3.1 hits zope.interface's __provides__ descriptor while
  # clearing cached class properties (reproduced on pinned Nixpkgs). Reviewed
  # 2026-11-06 at b1b875982b17dabde9b4a37f3e229e74913e6db3. No upstream fix
  # is known; remove when the descriptor handling is fixed.
  xmlschema = pyprev.xmlschema.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./xmlschema-zope-interface.patch ];
  });
}
