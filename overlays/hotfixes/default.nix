{ final, prev }:
# Noctalia's patch bundle is applied at explicit positions by ../noctalia.nix.
let
  packageOverrides = [
    (import ./home-assistant-cli.nix { inherit prev; })
    (import ./matrix-synapse.nix { inherit final prev; })
    (import ./obs-replay-source.nix { inherit prev; })
    (import ./playwright-mcp.nix { inherit final; })
  ];

  # Keep these extensions in the same order as the former inline list.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    ((import ./playwright.nix) final.fetchFromGitHub)
    (import ./pytest-playwright.nix)
    (import ./pysaml2.nix)
    (import ./xmlschema.nix)
  ];

  mergedPackages = builtins.foldl' (merged: overlay: merged // overlay) { } packageOverrides;
in
mergedPackages
// {
  inherit pythonPackagesExtensions;
}
