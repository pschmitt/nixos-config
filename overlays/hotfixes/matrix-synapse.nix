{ final, prev }:
{
  # SAML-enabled tests and runtime require pytz, omitted from the pinned extra.
  # Local fix; remove when the package includes pytz. Reviewed 2026-11-10 at
  # Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6; tests pass with it.
  matrix-synapse-unwrapped = prev.matrix-synapse-unwrapped.overridePythonAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.python3Packages.pytz ];
    propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ final.python3Packages.pytz ];
  });
}
