_pyfinal: pyprev: {
  # preCheck realizes playwright-driver.browsers with doCheck=false; that
  # WebKit closure fails for missing libmanette. Reviewed 2026-11-06 at
  # Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396. No upstream fix is
  # known; remove when the browser closure is fixed.
  pytest-playwright = pyprev.pytest-playwright.overridePythonAttrs (_old: {
    preCheck = "";
  });
}
