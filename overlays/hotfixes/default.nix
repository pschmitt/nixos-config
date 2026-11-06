{ final, prev }:
# Noctalia's patch bundle is applied at explicit positions by ../noctalia.nix.
let
  packageOverrides = [
    (import ./audacity.nix { inherit prev; })
    (import ./home-assistant-cli.nix { inherit final prev; })
    (import ./matrix-synapse.nix { inherit final prev; })
    (import ./obs-replay-source.nix { inherit prev; })
    (import ./playwright-mcp.nix { inherit final; })
    (import ./rxvt-unicode.nix { inherit prev; })
    (import ./shadowsocks-libev.nix { inherit prev; })
    (import ./squeekboard.nix { inherit prev; })
    (import ./perl-dbd-csv.nix { inherit prev; })
  ];

  python313Packages = prev.python313Packages.overrideScope (
    finalPy: prevPy:
    ((import ./pipx.nix) finalPy prevPy) // ((import ./python-aodhclient.nix) finalPy prevPy)
  );

  # Keep these extensions in the same order as the former inline list.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    ((import ./playwright.nix) final.fetchFromGitHub)
    (import ./pytest-playwright.nix)
    (import ./torchcodec.nix)
    (import ./diff-cover.nix)
    (import ./websockify.nix)
    (import ./pysaml2.nix)
    (import ./xmlschema.nix)
  ];

  mergedPackages = builtins.foldl' (merged: overlay: merged // overlay) { } packageOverrides;
in
mergedPackages
// {
  inherit python313Packages pythonPackagesExtensions;
  pipx = final.python313Packages.pipx;
}
