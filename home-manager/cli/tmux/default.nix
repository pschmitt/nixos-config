# tmux config (formerly in yadm): ./config is linked file by file into
# ~/.config/tmux, so runtime state (e.g. resurrect/) can still live there.
# Plugins replace tpm, see ./plugins.nix.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  plugins = import ./plugins.nix { inherit inputs pkgs; };

  # $TMUX_PLUGIN_MANAGER_PATH with tpm's directory names
  pluginDir = pkgs.linkFarm "tmux-plugins" (
    map (p: {
      inherit (p) name;
      path = dirOf p.plugin.rtp;
    }) plugins
  );
in
{
  xdg = {
    configFile = {
      "tmux" = {
        source = ./config;
        recursive = true;
      };
      "tmux/plugins-nix.conf".text = lib.concatMapStrings (p: ''
        run-shell ${lib.escapeShellArg "${pluginDir}/${p.name}/${baseNameOf p.plugin.rtp}"}
      '') plugins;
    };
    dataFile."tpm".source = pluginDir;
  };
}
