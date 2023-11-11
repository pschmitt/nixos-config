{ inputs, lib, config, pkgs, ... }:

{
  home.packages = with pkgs; [ obs-cli ];

  programs.obs-studio = {
    enable = true;
    package = pkgs.unstable.obs-studio;
    plugins = with pkgs; [
      unstable.obs-studio-plugins.droidcam-obs
      unstable.obs-studio-plugins.obs-text-pthread
      unstable.obs-studio-plugins.obs-freeze-filter
      # obs-studio-plugins.obs-replay-source # https://github.com/NixOS/nixpkgs/pull/252191
    ];
  };

  home.file.".config/obs-studio/scripts/bounce.lua".source = (
    builtins.fetchurl {
      url = "https://raw.githubusercontent.com/pschmitt/obs-bounce/follow-item-visibility/bounce.lua";
      sha256 = "sha256-vZr+GLLI0hkYZuuiXVBaR+pK8ZRG+qZowJUXTxAPrvE=";
    }
  );
}
