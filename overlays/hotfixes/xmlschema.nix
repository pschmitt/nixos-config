_pyfinal: pyprev: {
  # xmlschema 4.3.1 hits zope.interface's __provides__ descriptor while
  # clearing cached class properties (reproduced on pinned Nixpkgs). Reviewed
  # 2026-11-06 at 1d060086d60cb76a40cf37109f979d88a5bd6396. No upstream fix
  # is known; remove when the descriptor handling is fixed.
  xmlschema = pyprev.xmlschema.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./xmlschema-zope-interface.patch ];
  });
}
