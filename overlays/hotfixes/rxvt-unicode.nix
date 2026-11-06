{ prev }:
{
  # GCC's C++20 std::lerp conflicts with rxvt-unicode's overloads. Retained
  # pending checks against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  rxvt-unicode-unwrapped = prev.rxvt-unicode-unwrapped.overrideAttrs (old: {
    env = (old.env or { }) // {
      NIX_CFLAGS_COMPILE = "-std=gnu++17";
    };
  });
}
