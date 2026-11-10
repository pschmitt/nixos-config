_pyfinal: pyprev: {
  # xmlschema 4.3.1 hits zope.interface's __provides__ descriptor during
  # Synapse's SAML tests. Local fix; remove when descriptor handling is fixed.
  # Reviewed 2026-11-10 at Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6:
  # unpatched Synapse fails with AttributeError: __provides__; patched tests pass.
  xmlschema = pyprev.xmlschema.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./xmlschema-zope-interface.patch ];
  });
}
