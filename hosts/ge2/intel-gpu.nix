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

  hardware.intelgpu.driver = "xe";
  # hardware.intelgpu.vaapiDriver = "intel-media-driver";
}
