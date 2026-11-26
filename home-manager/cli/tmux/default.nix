# tmux config (formerly in yadm): ./config is linked file by file into
# ~/.config/tmux, so runtime state (e.g. resurrect/) can still live there.
# Plugins replace tpm, see ./plugins.nix.
{
  config,
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  plugins = import ./plugins.nix { inherit inputs pkgs; };

  # The status line is plain tmux formats (no #() jobs, which status-interval 1
  # would rerun every second). In conditionals, `,` and `#` need a `#`.
  hostColor =
    let
      color = config.dotfiles.promptColor;
    in
    if builtins.match "[0-9]+" color != null then "colour${color}" else color;
  hostAlias =
    if config.dotfiles.promptHostAlias != null then config.dotfiles.promptHostAlias else hostname;
  sessionLabel = "#{?#{==:#S,main},,#{?#{==:#S,bg},#[fg=##6c7570#,bold]bg ,#{?#{==:#S,scratchpad},#[fg=##035728#,bold]📔 ,#[fg=red#,bold]#S }}}";

  windowIcons = import ./window-icons.nix;
  windowIcon = lib.foldr (
    entry: rest:
    "#{?#{m/r:^(${lib.concatStringsSep "|" entry.commands})$,#{pane_current_command}},${entry.icon},${rest}}"
  ) windowIcons.default windowIcons.icons;

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
      # Sourced first by config/tmux.conf: the paths Home Manager knows
      "tmux/env.conf".text = ''
        %if #{==:#{TMPDIR},}
        TMPDIR=/tmp
        %else
        TMPDIR="$TMPDIR"
        %endif
        setenv -gF TMPDIR "#{TMPDIR}"

        setenv -g XDG_CACHE_HOME ${lib.escapeShellArg config.xdg.cacheHome}
        setenv -g XDG_CONFIG_HOME ${lib.escapeShellArg config.xdg.configHome}
        setenv -g XDG_DATA_HOME ${lib.escapeShellArg config.xdg.dataHome}
        setenv -g TMUX_CONFIG_HOME ${lib.escapeShellArg "${config.xdg.configHome}/tmux"}
        setenv -g TMUX_BIN_HOME ${lib.escapeShellArg "${config.xdg.configHome}/tmux/bin"}
        setenv -g TMUX_PLUGIN_MANAGER_PATH ${lib.escapeShellArg "${config.xdg.dataHome}/tpm"}
        TMUX_CONFIG_HOME=${lib.escapeShellArg "${config.xdg.configHome}/tmux"}
        TMUX_BIN_HOME=${lib.escapeShellArg "${config.xdg.configHome}/tmux/bin"}
        setenv -gF TMUX_VERSION '#{version}'

        # We *always* want completions in tmux sessions
        setenv -gr NO_COMPLETIONS
      '';
      # Sourced by config/tmux.conf before the plugins (prefix_highlight
      # rewrites status-right).
      "tmux/status.conf".text = ''
        set -g status-left " ${sessionLabel}#[fg=${hostColor}]${hostAlias} "
        set -g status-right "#{prefix_highlight} #{@load1} · %H:%M:%S "
        set -g window-status-format "#I ${windowIcon} #W"
        set -g window-status-current-format " #I ${windowIcon} #W #{?window_zoomed_flag,🔍 ,}"

        # The load average, from one loop per server (it ends with the server)
        # instead of a script per second
        if -F "#{!:#{@load1-updater}}" {
          set -g @load1-updater 1
          run-shell -b 'while read -r load _ </proc/loadavg && tmux set -g @load1 "$load"; do sleep 5; done'
        }
      '';
      "tmux/plugins-nix.conf".text = lib.concatMapStrings (p: ''
        run-shell ${lib.escapeShellArg "${pluginDir}/${p.name}/${baseNameOf p.plugin.rtp}"}
      '') plugins;
    };
    dataFile."tpm".source = pluginDir;
  };
}
