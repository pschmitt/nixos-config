{ final, prev }:
# Noctalia's patch bundle is applied at explicit positions by ../noctalia.nix.
let
  packageOverrides = [
    (import ./squeekboard.nix { inherit prev; })
    (import ./taskchampion-sync-server.nix { inherit final prev; })
  ];

  # Apply targeted workarounds to each Python package set.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (import ./pysaml2.nix)
    (import ./rich.nix { inherit (final) lib; })
  ];

  mergedPackages = builtins.foldl' (merged: overlay: merged // overlay) { } packageOverrides;
in
mergedPackages
// {
  inherit pythonPackagesExtensions;
  pipx = final.python313Packages.pipx;
}
