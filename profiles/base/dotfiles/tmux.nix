{
  lib,
  options,
  pkgs,
  ...
}:
let
  hasConfigBeforePlugins = options.programs.tmux ? extraConfigBeforePlugins;
  initialConfig = ''
    set -g set-titles on
    set -g mouse on
    set -g default-shell ${pkgs.zsh}/bin/zsh
  '';
in
{
  programs.tmux = {
    enable = true;
    clock24 = true;
    newSession = true;
    terminal = "tmux-direct";
    aggressiveResize = true;
    # Set prefix to Ctrl-a
    shortcut = "a";
    keyMode = "vi";
    extraConfig = lib.optionalString (!hasConfigBeforePlugins) initialConfig + ''
      # binds
      # switch to main session
      unbind M
      bind M switch-client -t main

      # vertical split
      unbind S
      bind S split-window -v

      # disable confirmation when killing pane
      unbind x
      bind x kill-pane

      # Select next/previous pane
      unbind Tab
      bind Tab select-pane -t:.+
      unbind BTab
      bind BTab select-pane -t:.-
    '';
    plugins = with pkgs.tmuxPlugins; [
      fuzzback # prefix-?
      mode-indicator
      pain-control
      sensible
    ];
  }
  // lib.optionalAttrs hasConfigBeforePlugins {
    extraConfigBeforePlugins = initialConfig;
  };
}
