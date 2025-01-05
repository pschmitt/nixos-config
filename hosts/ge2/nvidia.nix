# https://nixos.wiki/wiki/Nvidia
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    # Uncomment to completely disable the NVIDIA GPU
    # inputs.hardware.nixosModules.common-gpu-nvidia-disable
  ];

  # FIXME Last known working version was:
  # - pkgs.linuxPackages_6_11 ie. Linux ge2 6.11.10 #1-NixOS SMP PREEMPT_DYNAMIC Fri Nov 22 14:39:56 UTC 2024 x86_64 GNU/Linux
  # - NVIDIA Driver Version: 560.35.03 (NVML Version: 12.560.35.03)
  # - nixpkgs:
  #   "nixpkgs": {
  #     "locked": {
  #       "lastModified": 1734424634,
  #       "narHash": "sha256-cHar1vqHOOyC7f1+tVycPoWTfKIaqkoe1Q6TnKzuti4=",
  #       "owner": "NixOS",
  #       "repo": "nixpkgs",
  #       "rev": "d3c42f187194c26d9f0309a8ecc469d6c878ce33",
  #       "type": "github"
  #     },
  #     "original": {
  #       "owner": "NixOS",
  #       "ref": "nixos-unstable",
  #       "repo": "nixpkgs",
  #       "type": "github"
  #     }
  #   },

  # Newer kernels might not be compatible with the Nvidia crap.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_11;
  # boot.kernelPackages = lib.mkForce pkgs.linuxPackages_zen;

  hardware.graphics.enable = true;

  # FIX For gnome apps not opening
  environment.sessionVariables = {
    GSK_RENDERER = "ngl";
  };

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

  # virtualisation.docker.enableNvidia = true;
  # virtualisation.containers.cdi.dynamic.nvidia.enable = true;
  hardware.nvidia-container-toolkit.enable = true;
}
