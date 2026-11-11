{ final, prev }:
# Noctalia's patch bundle is applied at explicit positions by ../noctalia.nix.
let
  packageOverrides = [
    (import ./matrix-synapse.nix { inherit final prev; })
    (import ./onnxruntime.nix { inherit prev; })
    (import ./squeekboard.nix { inherit prev; })
    (import ./stalwart-cli.nix { inherit final prev; })
    (import ./stalwart.nix { inherit final prev; })
    (import ./taskchampion-sync-server.nix { inherit final prev; })
    (import ./taskwarrior.nix { inherit final prev; })
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
