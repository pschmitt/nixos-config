{
  inputs,
  ...
}:
{
  imports = [
    # Disable intel i915
    # inputs.hardware.nixosModules.common-gpu-intel-disable

    # INTEL (module)
    inputs.hardware.nixosModules.common-gpu-intel
  ];

  # Force xe driver
  # https://wiki.archlinux.org/title/Intel_graphics#Testing_the_new_experimental_Xe_driver
  boot.kernelParams = [
    "i915.force_probe=!a7a0"
    "xe.force_probe=a7a0"
  ];
  hardware.intelgpu.driver = "xe";
  hardware.intelgpu.vaapiDriver = "intel-media-driver";
}
