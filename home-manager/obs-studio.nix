{ inputs, lib, osConfig, config, pkgs, ... }:

let
  enableNvidiaOffload = osConfig.hardware.nvidia.prime.offload.enable;
  obs-nvidia = pkgs.writeShellScriptBin "obs-nvidia" ''
    nvidia-offload ${pkgs.obs-studio}/bin/obs "$@"
  '';
  obs-nvidia-custom = pkgs.writeShellScriptBin "obs-nvidia-custom" ''
    ${obs-nvidia}/bin/obs-nvidia \
        --minimize-to-tray \
        --startvirtualcam \
        --scene "Joining soon" \
        "$@"
  '';
in

{
  home.packages = [
    pkgs.obs-cli
  ]
  ++ lib.optional enableNvidiaOffload obs-nvidia
  ++ lib.optional enableNvidiaOffload obs-nvidia-custom;

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
