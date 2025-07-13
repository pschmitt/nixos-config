{
  lib,
  osConfig,
  pkgs,
  ...
}:

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
  home.packages =
    [
      pkgs.obs-cli
      (pkgs.writeShellScriptBin "obs-studio-ustreamer" ''
        ${pkgs.ustreamer}/bin/ustreamer -d /dev/video10 "$@"
      '')
    ]
    ++ lib.optional enableNvidiaOffload obs-nvidia
    ++ lib.optional enableNvidiaOffload obs-nvidia-custom;

  programs.obs-studio = {
    enable = true;
    package = pkgs.obs-studio;
    plugins = with pkgs.obs-studio-plugins; [
      droidcam-obs
      obs-text-pthread
      obs-freeze-filter
      # FIXME OBS Replay Source build is broken with obs 31
      # There's an untagged 1.8.1 which *might* work:
      # https://github.com/exeldro/obs-replay-source/commit/18b0b8b3519ee7bb192ae19adce81b4dbb2ba9c2
      # obs-replay-source
    ];
  };

  home.file.".config/obs-studio/scripts/bounce.lua".source = (
    builtins.fetchurl {
      url = "https://raw.githubusercontent.com/pschmitt/obs-bounce/4a01d2096a3ffa886d6bbfb97c27301065e33f55/bounce.lua";
      sha256 = "1w1ks5nf4icgbqmbcp8cvmv30426srhcspjad3gmkiin6vxz42ny";
    }
  );
}
