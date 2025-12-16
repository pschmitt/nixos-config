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

  # Newer kernels might not be compatible with the Nvidia crap.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_18;

  # boot.kernelPackages = lib.mkForce pkgs.linuxPackages_zen;

  hardware = {
    graphics.enable = true;

    nvidia = {
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
      # https://github.com/nixos/nixpkgs/blob/master/pkgs/os-specific/linux/nvidia-x11/default.nix
      package = config.boot.kernelPackages.nvidiaPackages.latest;
      # package = config.boot.kernelPackages.nvidiaPackages.production;
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

    # XXX Both opts below have been deprecated in favor of
    # hardware.nvidia-container-toolkit.enable:
    # - virtualisation.docker.enableNvidia = true;
    # - virtualisation.containers.cdi.dynamic.nvidia.enable = true;
    nvidia-container-toolkit.enable = true;
  };

  # FIX For gnome apps not opening
  environment.sessionVariables = {
    GSK_RENDERER = "ngl";
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];
}
