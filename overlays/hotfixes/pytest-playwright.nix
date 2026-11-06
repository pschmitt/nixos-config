_pyfinal: pyprev: {
  # preCheck realizes playwright-driver.browsers with doCheck=false; that
  # WebKit closure fails for missing libmanette. Reviewed 2026-11-06 at
  # Nixpkgs b1b875982b17dabde9b4a37f3e229e74913e6db3. No upstream fix is
  # known; remove when the browser closure is fixed.
  pytest-playwright = pyprev.pytest-playwright.overridePythonAttrs (_old: {
    preCheck = "";
  });
}
