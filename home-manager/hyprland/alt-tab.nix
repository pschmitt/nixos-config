{ lib, ... }:
{
  # Mirrors ~/.config/hypr/config.d/alt-tab.conf.
  # Docs: https://wiki.hyprland.org/Configuring/Uncommon-tips--tricks/#alt-tab-behaviour
  wayland.windowManager.hyprland = {
    settings = {
      # Alt-tab helper bindings from alt-tab.conf.
      bind = lib.mkAfter [
        "ALT, TAB, exec, $bin_dir/alt-tab.sh enable 'down'"
        "ALT SHIFT, TAB, exec, $bin_dir/alt-tab.sh enable 'up'"
        "ALT, Return, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return, class:alttab"
        "ALT SHIFT, Return, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return, class:alttab"
        "ALT, escape, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , escape,class:alttab"
        "ALT SHIFT, escape, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , escape,class:alttab"
      ];
      bindrt = lib.mkAfter [
        "ALT, ALT_L, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return,class:alttab"
        "ALT SHIFT, ALT_L, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return,class:alttab"
      ];
      workspace = lib.mkAfter [
        "special:alttab, gapsout:200, gapsin:200, bordersize:0"
      ];
      windowrule = lib.mkAfter [
        "noanim, class:alttab"
        "stayfocused, class:alttab"
        "workspace special:alttab, class:alttab"
        "bordersize 0, class:alttab"
      ];
    };

    submaps.alttab.settings.bind = [
      "ALT, tab, sendshortcut, , tab, class:alttab"
      "ALT SHIFT, tab, sendshortcut, shift, tab, class:alttab"
    ];
  };
}
