{ final, prev }:
{
  # aws-lc-sys requires the system library with current Rust build hooks.
  # Local fix; remove when Nixpkgs supplies it. Reviewed 2026-11-11 at
  # f4a03c008967841f2a0b3cb7c436fc6fc31671f6: aarch64 failed; x86_64 built.
  stalwart-cli = prev.stalwart-cli.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
    buildInputs = (old.buildInputs or [ ]) ++ [ final.aws-lc ];
  });
}
