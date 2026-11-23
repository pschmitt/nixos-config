{ prev }:
{
  # Signal rejects attachment upload forms without uploadLength (HTTP 400).
  # Backport: https://github.com/mautrix/signal/commit/e2e994f99f8dfffe5ad1cc88a2d36449639a609e
  # Remove when nixpkgs ships mautrix-signal >= 26.11 with this fix.
  # Reviewed 2026-11-23: b1b875982b17 ships 26.08, which needs the patch.
  # 2786a2a72088 ships 26.11 and contains the backport commit upstream.
  mautrix-signal = prev.mautrix-signal.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++ prev.lib.optional (prev.lib.versionOlder old.version "26.11") ./mautrix-signal-upload-length.patch;
  });
}
