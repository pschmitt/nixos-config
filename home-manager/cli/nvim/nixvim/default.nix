# Nixvim configuration: Nix declares the plugins and tools, the editor
# behaviour (options, keymaps, autocmds, user commands) stays in ../config.
{ lib, pkgs, ... }:
let
  configDir = ../config;
in
{
  imports = [
    ./completion.nix
    ./lsp.nix
    ./plugins.nix
  ];

  vimAlias = true;
  withRuby = false;
  withPython3 = false;

  clipboard.providers.wl-copy.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isLinux;

  globals = {
    mapleader = " ";
    maplocalleader = ",";
  };

  colorschemes.onedark = {
    enable = true;
    settings = {
      style = "darker";
      code_style.comments = "none";
    };
  };

  # Ship ../config (lua/, after/, snippets/) as-is: in ~/.config/nvim, or in
  # the wrapped runtime path for nvim-nightly.
  extraFiles = lib.listToAttrs (
    map (
      file:
      lib.nameValuePair (lib.removePrefix "${toString configDir}/" (toString file)) { source = file; }
    ) (lib.filesystem.listFilesRecursive configDir)
  );

  # Options (and user commands) before any plugin is set up, the rest after.
  extraConfigLuaPre = ''
    require("config.options")
  '';
  extraConfigLuaPost = ''
    require("config.keymaps")
    require("config.autocmds")
    require("config.local")
  '';
}
