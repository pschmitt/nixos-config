{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  binDir = "~/.config/hypr/bin";
  luaBind = import ../lib/lua-bind.nix { inherit lib; };
in
{
  # Docs: https://wiki.hyprland.org/Configuring/Uncommon-tips--tricks/#alt-tab-behaviour

  home.packages = [
    (pkgs.writeShellScriptBin "grim-hyprland" ''
      exec -a $0 ${inputs.grim-hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/grim "$@"
    '')
  ];

  wayland.windowManager.hyprland = {
    settings = {
      bind = [
        (luaBind.mkBind "ALT, TAB, exec, ${binDir}/alt-tab.sh enable 'down'")
        (luaBind.mkBind "ALT SHIFT, TAB, exec, ${binDir}/alt-tab.sh enable 'up'")
        (luaBind.mkBind "ALT, Return, exec, ${binDir}/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return, class:alttab")
        (luaBind.mkBind "ALT SHIFT, Return, exec, ${binDir}/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return, class:alttab")
        (luaBind.mkBind "ALT, escape, exec, ${binDir}/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , escape,class:alttab")
        (luaBind.mkBind "ALT SHIFT, escape, exec, ${binDir}/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , escape,class:alttab")
        (luaBind.mkReleaseTransparentBind "ALT, ALT_L, exec, ${binDir}/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return,class:alttab")
        (luaBind.mkReleaseTransparentBind "ALT SHIFT, ALT_L, exec, ${binDir}/alt-tab.sh disable ; hyprctl -q dispatch sendshortcut , return,class:alttab")
      ];
      workspace_rule = [
        {
          workspace = "special:alttab";
          gaps_out = 200;
          gaps_in = 200;
          border_size = 0;
        }
      ];
      window_rule = map luaBind.mkWindowRule [
        "no_anim on, match:class alttab"
        "stay_focused on, match:class alttab"
        "workspace special:alttab, match:class alttab"
        "border_size 0, match:class alttab"
      ];
    };

    submaps.alttab.settings.bind = [
      {
        _args = [
          "ALT + tab"
          (luaBind.sendShortcut "" "tab" "class:alttab")
        ];
      }
      {
        _args = [
          "ALT + SHIFT + tab"
          (luaBind.sendShortcut "shift" "tab" "class:alttab")
        ];
      }
    ];
  };
}
