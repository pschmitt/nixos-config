# https://nixos.wiki/wiki/Nvidia
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    # Uncomment to completely disable the NVIDIA GPU
    # inputs.hardware.nixosModules.common-gpu-nvidia-disable
  ];

  # https://discourse.nixos.org/t/nixos-using-integrated-gpu-for-display-and-external-gpu-for-compute-a-guide/12345
  # boot.blacklistedKernelModules = [ "nouveau" "nvidia_drm" "nvidia_modeset" "nvidia" ];
  # boot.extraModulePackages = with pkgs; [
  #   linuxPackages_latest.nvidia_x11
  # ];
  # environment.systemPackages = with pkgs; [
  #   linuxPackages_latest.nvidia_x11
  # ];

  # FIX till pr#358047 is available on nixpkgs-unstable
  # https://nixpkgs-tracker.ocfox.me/?pr=358047
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_11;

  hardware.graphics.enable = true;

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Do not disable this unless your GPU is unsupported or if you have a good reason to.
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # package = config.boot.kernelPackages.nvidiaPackages.beta;
    # package = config.boot.kernelPackages.nvidiaPackages.vulkan_beta;

    prime = {
      sync.enable = false;

      offload = {
        enable = true;
        enableOffloadCmd = true;
      };

      # Make sure to use the correct Bus ID values for your system!
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # virtualisation.docker.enableNvidia = true;
  # virtualisation.containers.cdi.dynamic.nvidia.enable = true;
  hardware.nvidia-container-toolkit.enable = true;
}
