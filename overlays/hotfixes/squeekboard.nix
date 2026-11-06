{ prev }:
{
  # Rust's libc declaration also needs close()'s return type. Retained pending
  # validation against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  squeekboard = prev.squeekboard.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/vkeyboard.rs \
        --replace-fail 'fn close(fd: i32);' 'fn close(fd: i32) -> i32;'
    '';
  });
}
