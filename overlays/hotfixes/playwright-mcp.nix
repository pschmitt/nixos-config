{ final }:
{
  # Base build fails because WebKit's minibrowser lacks libmanette. Nixpkgs
  # [Nixpkgs PR #563824](https://github.com/NixOS/nixpkgs/pull/563824) fixes
  # its closure. Reviewed 2026-11-06 at
  # 1d060086d60cb76a40cf37109f979d88a5bd6396;
  # remove this master substitution when the PR reaches the pin.
  playwright-mcp = final.master.playwright-mcp;
}
