{
  inputs,
  pkgs,
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
  # lspci -nn | grep -Ei "VGA.*Intel"
  # 00:02.0 VGA compatible controller [0300]: Intel Corporation Raptor Lake-P [Iris Xe Graphics] [8086:a7a0] (rev 04)
  #                                                                                                    ^^^^
  boot.kernelParams = [
    "i915.force_probe=!a7a0"
    "xe.force_probe=a7a0"
  ];
  hardware.intelgpu.driver = "xe";
  hardware.intelgpu.vaapiDriver = "intel-media-driver";

  environment.systemPackages = [ pkgs.intel-gpu-tools ];
}
