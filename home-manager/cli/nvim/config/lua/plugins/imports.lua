-- lazyvim-nix only imports "plugins", pull in the subdirectories as well
return {
  { import = "plugins.coding" },
  { import = "plugins.misc" },
  { import = "plugins.ui" },
}
