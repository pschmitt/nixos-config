{ ... }:
{
  # Steel is the only headless browser we run. The Chromium container and
  # Browserless modules are kept in services/headless-browsers/ for later use
  # but are intentionally not imported anymore.
  imports = [
    ../services/headless-browsers/steel.nix
  ];
}
