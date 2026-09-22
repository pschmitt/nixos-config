{ lib, ... }:
let
  defaultDevices = {
    eaton-ups = "0463:ffff";
    google-coral-1 = "1a6e:089a";
    google-coral-2 = "18d1:9302";
    zbt-2 = "303a:831a";
    zwa-2 = "303a:4001";
    zbdongle-e = "1a86:55d4";
    zwave-stick = "0658:0200";
    rfxtrx = "0403:6001";
    ais-sdr = "0bda:2838";
  };
in
{
  options.services.kvm-usb-passthrough = {
    enable = lib.mkEnableOption "Home Assistant KVM USB passthrough watchdog";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "home-assistant";
      description = "Libvirt KVM domain name to attach USB devices to.";
    };

    checkInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Seconds between passthrough checks.";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = defaultDevices;
      description = "Attribute set of device name to vendor:product USB ID.";
    };

    callbacks = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Shell callbacks to execute after successful device attachment.";
    };
  };
}
