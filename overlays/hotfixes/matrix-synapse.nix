{ final, prev }:
{
  # SAML-enabled checks fail without pytz, omitted from the pinned SAML extra.
  # No upstream fix is known. Reviewed 2026-11-06 at Nixpkgs
  # b1b875982b17dabde9b4a37f3e229e74913e6db3;
  # remove when the package includes pytz in that extra.
  matrix-synapse-unwrapped = prev.matrix-synapse-unwrapped.overridePythonAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.python3Packages.pytz ];
    propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ final.python3Packages.pytz ];
  });
}
