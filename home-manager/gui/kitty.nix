_: {
  programs.kitty = {
    enable = true;
    themeFile = "Nord";
    font = {
      name = "ComicCode Nerd Font";
      size = 14;
    };
    settings = {
      # Nord background override (slightly darker than stock Nord #2E3440)
      background = "#24282F";

      allow_remote_control = "yes";
      open_url_with = "firefox";
      confirm_os_window_close = 0;

      # Allow reading and writing clipboard and primary selection, do *not* ask
      # for permission
      # https://github.com/tmux/tmux/wiki/Clipboard#terminal-support---kitty
      clipboard_control = "write-primary write-clipboard read-clipboard read-primary no-append";

      # Tab bar
      tab_bar_edge = "bottom";
      tab_bar_margin_width = 0.0;
      tab_bar_margin_height = "0.0 0.0";
      tab_bar_style = "separator";
      tab_bar_align = "left";
      tab_separator = ''""'';
      tab_title_template = ''"{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab} {index} {title} "'';
      active_tab_foreground = "#A6A6A6";
      active_tab_background = "#000000";
      active_tab_font_style = "none";
      inactive_tab_foreground = "#717171";
      inactive_tab_background = "#2E2E2E";
      inactive_tab_font_style = "normal";
      tab_bar_background = "#2E2E2E";
      tab_bar_margin_color = "#2E2E2E";
    };
    keybindings = {
      "ctrl+page_up" = "next_tab";
      "ctrl+page_down" = "previous_tab";
      "ctrl+alt+t" = "combine | close_tab | launch --type=tab ~/bin/zhj tmux::attach";
      "ctrl+plus" = "change_font_size all +1.0";
      "ctrl+minus" = "change_font_size all -1.0";
      "ctrl+0" = "change_font_size all 0";
      "kitty_mod+p>y" = "kitten hints --type hyperlink";
    };
    extraConfig = ''
      mouse_map ctrl+left release ungrabbed mouse_handle_click link
    '';
  };
}
