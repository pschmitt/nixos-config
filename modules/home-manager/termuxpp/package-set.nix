{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  lockedSource = {
    type = "path";
    path = toString inputs.nixpkgs.outPath;
    narHash = inputs.nixpkgs.narHash;
  };
  lock = (pkgs.formats.json { }).generate "nixpp-flake.lock" {
    version = 7;
    root = "root";
    nodes = {
      root.inputs.nixpkgs = "nixpkgs";
      nixpkgs = {
        locked = lockedSource;
        original = {
          type = "path";
          path = toString inputs.nixpkgs.outPath;
        };
      };
    };
  };
  source = pkgs.runCommand "nixpp-nixpkgs" { } ''
    mkdir -p "$out"
    cp ${../../../overlays/termuxpp/default.nix} "$out/overlay.nix"
    cp ${../../../overlays/termuxpp/eza-stack.c} "$out/eza-stack.c"
    cp ${../../../overlays/termuxpp/rsync-search-only-ancestors.patch} "$out/rsync-search-only-ancestors.patch"
    cp ${../../../overlays/termuxpp/neovim-treesitter-async-tests.patch} "$out/neovim-treesitter-async-tests.patch"
    cp ${pkgs.writeText "nixpp-default.nix" ''
      args:
      import ${inputs.nixpkgs.outPath} (args // {
        overlays = (args.overlays or []) ++ [ (import ./overlay.nix) ];
      })
    ''} "$out/default.nix"
    cp ${pkgs.writeText "nixpp-flake.nix" ''
      {
        inputs.nixpkgs.url = "path:${inputs.nixpkgs.outPath}";
        outputs = { self, nixpkgs }: {
          legacyPackages.aarch64-linux = import nixpkgs {
            system = "aarch64-linux";
            config.allowUnfree = true;
            overlays = [ (import ./overlay.nix) ];
          };
          lib = nixpkgs.lib;
        };
      }
    ''} "$out/flake.nix"
    cp ${lock} "$out/flake.lock"
  '';
  targets = {
    nixpkgs = {
      type = "path";
      path = toString source;
    };
    termuxPkgs = {
      type = "path";
      path = toString inputs.termuxpp.outPath;
    };
  };
  registry = (pkgs.formats.json { }).generate "nixpp-registry.json" {
    version = 2;
    flakes = lib.mapAttrsToList (id: target: {
      from = {
        type = "indirect";
        inherit id;
      };
      to = target;
      exact = true;
    }) targets;
  };
in
{
  nix = {
    registry = lib.mapAttrs (_: target: { to = target; }) targets;
    settings.flake-registry = "file://${registry}";
    nixPath = [ "nixpkgs=${source}" ];
  };
  home.file.".local/share/nixpp/nixpkgs".source = source;
}
