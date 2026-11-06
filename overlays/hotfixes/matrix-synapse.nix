{ final, prev }:
{
  # SAML-enabled checks fail without pytz, omitted from the pinned SAML extra.
  # No upstream fix is known. Reviewed 2026-11-06 at Nixpkgs
  # 1d060086d60cb76a40cf37109f979d88a5bd6396;
  # remove when the package includes pytz in that extra.
  matrix-synapse-unwrapped = prev.matrix-synapse-unwrapped.overridePythonAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.python3Packages.pytz ];
    propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ final.python3Packages.pytz ];
  });
}
