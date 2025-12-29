{
  inputs,
  pkgs,
  ...
}:
{
  # Docs: https://wiki.hyprland.org/Configuring/Uncommon-tips--tricks/#alt-tab-behaviour

  home.packages = [
    (pkgs.writeShellScriptBin "grim-hyprland" ''
      exec -a $0 ${inputs.grim-hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/grim "$@"
    '')
  ];

  wayland.windowManager.hyprland = {
    settings = {
      # Alt-tab helper bindings from alt-tab.conf.
      bind = [
        "ALT, TAB, exec, $bin_dir/alt-tab.sh enable 'down'"
        "ALT SHIFT, TAB, exec, $bin_dir/alt-tab.sh enable 'up'"
        "ALT, Return, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return, class:alttab"
        "ALT SHIFT, Return, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return, class:alttab"
        "ALT, escape, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , escape,class:alttab"
        "ALT SHIFT, escape, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , escape,class:alttab"
      ];
      bindrt = [
        "ALT, ALT_L, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return,class:alttab"
        "ALT SHIFT, ALT_L, exec, $bin_dir/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return,class:alttab"
      ];
      workspace = [
        "special:alttab, gapsout:200, gapsin:200, bordersize:0"
      ];
      windowrule = [
        "no_anim on, match:class alttab"
        "stay_focused on, match:class alttab"
        "workspace special:alttab, match:class alttab"
        "border_size 0, match:class alttab"
      ];
    };

    submaps.alttab.settings.bind = [
      "ALT, tab, sendshortcut, , tab, class:alttab"
      "ALT SHIFT, tab, sendshortcut, shift, tab, class:alttab"
    ];
  };
}
