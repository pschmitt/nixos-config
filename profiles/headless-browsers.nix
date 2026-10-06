{ ... }:
{
  imports = [
    ../services/headless-browsers/browser-mcp-chromium-container.nix
    ../services/headless-browsers/browserless.nix
    ../services/headless-browsers/steel.nix
  ];
}
