{
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  enableNvidiaOffload = osConfig.hardware.nvidia.prime.offload.enable;
  obsAutostartExec = "${
    pkgs.writeShellApplication {
      name = "obs-hyprland-autostart";
      runtimeInputs = with pkgs; [
        coreutils
        findutils
        flatpak
        gawk
        gnugrep
        obs-studio
        procps
      ];
      text = builtins.readFile ./obs-autostart.sh;
    }
  }/bin/obs-hyprland-autostart";
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
    # FIXME ustreamer fails to build as of 2025-11-15
    # (pkgs.writeShellScriptBin "obs-studio-ustreamer" ''
    #   ${pkgs.ustreamer}/bin/ustreamer -d /dev/video10 "$@"
    # '')
  ]
  ++ lib.optional enableNvidiaOffload obs-nvidia
  ++ lib.optional enableNvidiaOffload obs-nvidia-custom;

  programs.obs-studio = {
    enable = true;
    package = pkgs.master.obs-studio;
    plugins = with pkgs.obs-studio-plugins; [
      # FIXME fails to build as of 2025-11-15
      # https://github.com/NixOS/nixpkgs/issues/461403
      # droidcam-obs

      obs-text-pthread
      obs-freeze-filter
      # FIXME OBS Replay Source build is broken with obs 31
      # There's an untagged 1.8.1 which *might* work:
      # https://github.com/exeldro/obs-replay-source/commit/18b0b8b3519ee7bb192ae19adce81b4dbb2ba9c2
      # obs-replay-source
    ];
  };

  xdg.desktopEntries."obs-studio-custom" = {
    name = "OBS Studio (Custom)";
    comment = "Start OBS with our custom flags";
    icon = "com.obsproject.Studio";
    exec = obsAutostartExec;
    terminal = false;
    settings = {
      TryExec = obsAutostartExec;
    };
  };

  home.file.".config/obs-studio/scripts/bounce.lua".source = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/pschmitt/obs-bounce/4a01d2096a3ffa886d6bbfb97c27301065e33f55/bounce.lua";
    sha256 = "1w1ks5nf4icgbqmbcp8cvmv30426srhcspjad3gmkiin6vxz42ny";
  };
}
