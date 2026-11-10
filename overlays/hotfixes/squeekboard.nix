{ prev }:
{
  # On x86_64-linux, Rust's libc declaration also needs close()'s return type.
  # Reviewed 2026-11-10 at Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6;
  # without this patch the build fails on invalid_runtime_symbol_definitions.
  # No upstream issue is known; remove when squeekboard fixes the declaration.
  squeekboard = prev.squeekboard.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/vkeyboard.rs \
        --replace-fail 'fn close(fd: i32);' 'fn close(fd: i32) -> i32;'
    '';
  });
}
