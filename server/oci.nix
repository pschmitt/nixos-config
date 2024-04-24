# https://github.com/NixOS/nixpkgs/pull/119856/
{ inputs, pkgs, ... }:
let
  snapPkg = inputs.nix-snapd.packages.${pkgs.system}.default;
in
{

  boot.kernelParams = [
    "nvme.shutdown_timeout=10"
    "nvme_core.shutdown_timeout=10"
    "libiscsi.debug_libiscsi_eh=1"
    "crash_kexec_post_notifiers"

    # VNC console
    "console=tty1"

    # x86_64-linux
    "console=ttyS0"

    # aarch64-linux
    "console=ttyAMA0,115200"
  ];

  # https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/configuringntpservice.htm#Configuring_the_Oracle_Cloud_Infrastructure_NTP_Service_for_an_Instance
  networking.timeServers = [ "169.254.169.254" ];

  services.snap.enable = true;
  systemd.services.snap-install-oracle-cloud-agent = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "snapd.service" ];
    requires = [ "network-online.target" "snapd.service" ];
    script = "${snapPkg}/bin/snap install oracle-cloud-agent --classic";
  };

  # TODO Add the udev rules from ./99-systemoci-persistent-names.rules
  services.udev.path = [ pkgs.oci-consistent-device-naming ];
  services.udev.packages = [ pkgs.oci-consistent-device-naming ];
}
