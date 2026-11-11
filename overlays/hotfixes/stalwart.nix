{ final, prev }:
{
  # Cargo's system-library defaults conflict with OpenSSL and the allocator's
  # prefixed symbols. Build the pinned vendored libraries until Nixpkgs fixes
  # these inputs.
  # Reviewed 2026-11-11 at Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6:
  # the aarch64 build failed; patched x86_64 build and version check passed.
  stalwart_0_16 = prev.stalwart_0_16.overrideAttrs (old: {
    # cargoSetupHook forces system detection during unpack, so override it
    # immediately before Cargo runs.
    preBuild = (old.preBuild or "") + ''
      export AWS_LC_SYS_USE_SYSTEM=0
      unset JEMALLOC_OVERRIDE
    '';
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      final.cmake
      final.perl
    ];
  });
}
