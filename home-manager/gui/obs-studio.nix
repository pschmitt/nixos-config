{
  inputs,
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
        procps
      ];
      text = builtins.readFile ./obs-autostart.sh;
    }
  }/bin/obs-hyprland-autostart";
  obs-nvidia = pkgs.writeShellScriptBin "obs-nvidia" ''
    nvidia-offload obs "$@"
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
    inputs.obs-cli.packages.${pkgs.stdenv.hostPlatform.system}.obs-cli

    (pkgs.writeShellScriptBin "obs-studio-ustreamer" ''
      ${pkgs.ustreamer}/bin/ustreamer -d /dev/video10 "$@"
    '')
  ]
  ++ lib.optionals enableNvidiaOffload [
    obs-nvidia
    obs-nvidia-custom
  ];

  programs.obs-studio = {
    enable = true;
    package = pkgs.master.obs-studio;
    plugins = with pkgs.obs-studio-plugins; [
      droidcam-obs
      obs-text-pthread
      obs-freeze-filter
      obs-replay-source
    ];
  };

  xdg.desktopEntries."obs-studio-custom" = {
    name = "OBS Studio (Custom)";
    comment = "Start OBS with our custom flags";
    icon = "com.obsproject.Studio";
    exec = obsAutostartExec;
    terminal = false;
  };

  home.file.".config/obs-studio/scripts/bounce.lua".source = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/pschmitt/obs-bounce/4a01d2096a3ffa886d6bbfb97c27301065e33f55/bounce.lua";
    sha256 = "1w1ks5nf4icgbqmbcp8cvmv30426srhcspjad3gmkiin6vxz42ny";
  };
}
