{ ... }:
{
  services.udev.extraRules = ''
    # Persistent symlink for INTEL GPU
    KERNEL=="card*", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x8086", ATTRS{class}=="0x03[0-9]*", SYMLINK+="dri/intel-gpu"
    KERNEL=="renderD*", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x8086", ATTRS{class}=="0x03[0-9]*", SYMLINK+="dri/intel-gpu-render"

    # Persistent symlink for NVIDIA GPU
    KERNEL=="card*", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x10de", ATTRS{class}=="0x03[0-9]*", SYMLINK+="dri/nvidia-gpu"
    KERNEL=="renderD*", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x10de", ATTRS{class}=="0x03[0-9]*", SYMLINK+="dri/nvidia-gpu-render"
  '';
}
