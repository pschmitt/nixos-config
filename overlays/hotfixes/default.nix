{ final, prev }:
# Noctalia's patch bundle is applied at explicit positions by ../noctalia.nix.
let
  packageOverrides = [
    (import ./home-assistant-cli.nix { inherit prev; })
    (import ./matrix-synapse.nix { inherit final prev; })
    (import ./squeekboard.nix { inherit prev; })
    (import ./stalwart.nix { inherit final prev; })
  ];

  # Apply targeted workarounds to each Python package set.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (import ./pysaml2.nix)
    (import ./xmlschema.nix)
  ];

  mergedPackages = builtins.foldl' (merged: overlay: merged // overlay) { } packageOverrides;
in
mergedPackages
// {
  inherit pythonPackagesExtensions;
  pipx = final.python313Packages.pipx;
}
