# tmux config (formerly in yadm): ./config is linked file by file into
# ~/.config/tmux, so runtime state (e.g. resurrect/) can still live there.
# Plugins replace tpm, see ./plugins.nix.
{
  config,
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
  # Mouse scrolling in less, man and bat inside tmux
  programs.zsh.initContent = lib.mkOrder 1450 ''
    if [[ -n "$TMUX" ]]
    then
      export PAGER="less --RAW-CONTROL-CHARS --quit-if-one-screen --mouse"
      export BAT_PAGER="$PAGER" MANPAGER="$PAGER"
    fi
  '';

  xdg = {
    configFile = {
      "tmux" = {
        source = ./config;
        recursive = true;
      };
      # Host color and alias for the status line (config/bin/tmux-status.sh)
      "tmux/host.sh".text = ''
        host_color=${lib.escapeShellArg config.dotfiles.promptColor}
        host_alias=${
          lib.escapeShellArg (
            if config.dotfiles.promptHostAlias != null then config.dotfiles.promptHostAlias else ""
          )
        }
      '';
      "tmux/plugins-nix.conf".text = lib.concatMapStrings (p: ''
        run-shell ${lib.escapeShellArg "${pluginDir}/${p.name}/${baseNameOf p.plugin.rtp}"}
      '') plugins;
    };
    dataFile."tpm".source = pluginDir;
  };
}
