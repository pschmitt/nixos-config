{ prev }:
{
  # C23 glibc headers trigger discarded-qualifier with -Werror. Retained
  # pending checks against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  shadowsocks-libev = prev.shadowsocks-libev.overrideAttrs (old: {
    env = (old.env or { }) // {
      NIX_CFLAGS_COMPILE = "-Wno-error=discarded-qualifiers";
    };
  });
}
