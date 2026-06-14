{
  inputs,
  config,
  pkgs,
  ...
}:

{
  virtualisation = {
    spiceUSBRedirection.enable = true;

    libvirtd = {
      enable = true;
      onShutdown = "shutdown";
    };
  };

  system.nssDatabases.hosts = [
    "libvirt"
    "libvirt_guest"
  ];
}
