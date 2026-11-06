fetchFromGitHub: _pyfinal: pyprev: {
  # The pinned Playwright 1.63.0 source hash mismatches GitHub codeload.
  # No upstream fix is known. Reviewed 2026-11-06 at Nixpkgs
  # b1b875982b17dabde9b4a37f3e229e74913e6db3;
  # remove when nixpkgs' source hash matches the tag archive.
  playwright = pyprev.playwright.overridePythonAttrs (_old: {
    src = fetchFromGitHub {
      owner = "microsoft";
      repo = "playwright-python";
      tag = "v${pyprev.playwright.version}";
      hash = "sha256-RwIn+0EcHnStjORVFmT7gp4bGjl+qer1FgtI3+aPF2w=";
    };
  });
}
