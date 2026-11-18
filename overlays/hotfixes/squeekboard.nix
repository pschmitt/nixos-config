{ prev }:
{
  # On x86_64-linux, Rust's libc declaration also needs close()'s return type.
  # Reviewed 2026-11-18 at Nixpkgs 1a08097fc1ed85575db39763b2c4a5d8970a37ba:
  # its upstream patch fixes the argument type but still omits the return type;
  # the unmodified build fails and this workaround builds successfully.
  # Remove when squeekboard fixes the full declaration.
  squeekboard = prev.squeekboard.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/vkeyboard.rs \
        --replace-fail 'fn close(fd: i32);' 'fn close(fd: i32) -> i32;'
    '';
  });
}
