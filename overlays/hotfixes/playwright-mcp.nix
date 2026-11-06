{ final }:
{
  # Base build fails because WebKit's minibrowser lacks libmanette. Nixpkgs
  # [Nixpkgs PR #563824](https://github.com/NixOS/nixpkgs/pull/563824) fixes
  # its closure. Reviewed 2026-11-06 at
  # b1b875982b17dabde9b4a37f3e229e74913e6db3;
  # remove this master substitution when the PR reaches the pin.
  playwright-mcp = final.master.playwright-mcp;
}
