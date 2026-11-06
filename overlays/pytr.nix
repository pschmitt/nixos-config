{ prev }:
{
  # Local runtime integration: use system Chromium from PATH instead of
  # downloading Playwright's browser bundle. Keep while pytr offers no browser
  # path option.
  pytr = prev.pytr.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/pytr-use-system-chromium.patch ];
  });
}
