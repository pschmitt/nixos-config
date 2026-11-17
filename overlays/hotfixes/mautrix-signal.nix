{ prev }:
{
  # Signal rejects attachment upload forms without uploadLength (HTTP 400).
  # Backport: https://github.com/mautrix/signal/commit/e2e994f99f8dfffe5ad1cc88a2d36449639a609e
  # Remove when nixpkgs ships mautrix-signal >= 26.11 with this fix.
  # Reviewed 2026-11-17: nixpkgs d5cc6833999746cffdfe0598f7bc801a57b887a9
  # ships 26.10 without the parameter; validation is the target deployment.
  mautrix-signal = prev.mautrix-signal.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mautrix-signal-upload-length.patch ];
  });
}
