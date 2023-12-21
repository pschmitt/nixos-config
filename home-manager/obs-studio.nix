{ lib, osConfig, pkgs, ... }:

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
    (pkgs.writeShellScriptBin "obs-studio" ''
      ${pkgs.flatpak}/bin/flatpak run com.obsproject.Studio "$@"
    '')
    (pkgs.writeShellScriptBin "obs-studio-custom" ''
      ${pkgs.flatpak}/bin/flatpak run com.obsproject.Studio \
        --minimize-to-tray \
        --startvirtualcam \
        --scene "Joining soon" \
        --disable-shutdown-check \
        "$@"
    '')
  ]
  ++ lib.optional enableNvidiaOffload obs-nvidia
  ++ lib.optional enableNvidiaOffload obs-nvidia-custom;

  programs.obs-studio = {
    enable = false;
    package = pkgs.unstable.obs-studio;
    plugins = with pkgs; [
      unstable.obs-studio-plugins.droidcam-obs
      unstable.obs-studio-plugins.obs-text-pthread
      unstable.obs-studio-plugins.obs-freeze-filter
      # obs-studio-plugins.obs-replay-source # https://github.com/NixOS/nixpkgs/pull/252191
    ];
  };

  services.flatpak = {
    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      "flathub-beta" = "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    };
    packages = [
      # NOTE The "//" are here cause we omitted the cpu arch
      "flathub:app/com.github.tchx84.Flatseal//stable" # obs requires a few permission tweaks
      "flathub:app/com.obsproject.Studio//stable"
      "flathub:runtime/com.obsproject.Studio.Plugin.DroidCam//stable"
      "flathub:runtime/com.obsproject.Studio.Plugin.NDI//stable"
    ];
    overrides = {
      "com.obsproject.Studio" = {
        filesystems = [
          "/nix:ro"
          "/run/current-system/sw/bin:ro"
        ];
      };
    };
  };

  # TODO Install obs plugins into ~/.var/app/com.obsproject.Studio/config/obs-studio/plugins
  # IMPORTANT: This would require to build them with GLIBC 2.32 (or 2.35 which
  # is what ldd --version reports in the flatpak)
  # - obs-text-pthread (optional, it does seem broken in flatpak obs)
  # - obs-text-pango
  # - freeze-filter (use the precompiled archive)
  # - replay-source (use the precompiled archive)

  home.file.".config/obs-studio/scripts/bounce.lua".source = (
    builtins.fetchurl {
      url = "https://raw.githubusercontent.com/pschmitt/obs-bounce/follow-item-visibility/bounce.lua";
      sha256 = "sha256-vZr+GLLI0hkYZuuiXVBaR+pK8ZRG+qZowJUXTxAPrvE=";
    }
  );
}
