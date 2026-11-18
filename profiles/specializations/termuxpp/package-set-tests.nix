{ source }:
let
  legacy = import source { system = "aarch64-linux"; };
  flake = (builtins.getFlake (toString source)).legacyPackages.aarch64-linux;
  check =
    pkgs:
    assert builtins.pathExists (source + "/rsync-search-only-ancestors.patch");
    assert builtins.pathExists (source + "/neovim-treesitter-async-tests.patch");
    {
      rsync = pkgs.rsync.drvPath;
      neovim = pkgs.neovim-unwrapped.drvPath;
      nixos-rebuild-ng = pkgs.nixos-rebuild-ng.drvPath;
    };
in
{
  legacy = check legacy;
  flake = check flake;
}
