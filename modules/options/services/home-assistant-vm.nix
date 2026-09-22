{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.home-assistant-vm;
  defaultDomainXml = pkgs.writeText "${cfg.domainName}.xml" ''
    <domain type='kvm'>
      <name>${cfg.domainName}</name>
      <uuid>${cfg.uuid}</uuid>
      <metadata>
        <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
          <libosinfo:os id="http://libosinfo.org/linux/2022"/>
        </libosinfo:libosinfo>
      </metadata>
      <memory unit='KiB'>${toString cfg.memoryKiB}</memory>
      <currentMemory unit='KiB'>${toString cfg.memoryKiB}</currentMemory>
      <vcpu placement='static'>${toString cfg.vcpu}</vcpu>
      <os firmware='efi'>
        <type arch='x86_64' machine='q35'>hvm</type>
        <firmware>
          <feature enabled='no' name='enrolled-keys'/>
          <feature enabled='no' name='secure-boot'/>
        </firmware>
        <nvram format='raw'>${cfg.nvramPath}</nvram>
        <boot dev='hd'/>
      </os>
      <features>
        <acpi/>
        <apic/>
        <vmport state='off'/>
      </features>
      <cpu mode='host-passthrough' check='none' migratable='on'/>
      <clock offset='utc'>
        <timer name='rtc' tickpolicy='catchup'/>
        <timer name='pit' tickpolicy='delay'/>
        <timer name='hpet' present='no'/>
      </clock>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <pm>
        <suspend-to-mem enabled='no'/>
        <suspend-to-disk enabled='no'/>
      </pm>
      <devices>
        <disk type='file' device='disk'>
          <driver name='qemu' type='qcow2'/>
          <source file='${cfg.diskImage}'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        <controller type='usb' index='0' model='qemu-xhci' ports='15'/>
        <controller type='pci' index='0' model='pcie-root'/>
        <interface type='bridge'>
          <mac address='${cfg.macAddress}'/>
          <source bridge='${cfg.bridgeName}'/>
          <model type='virtio'/>
        </interface>
        <serial type='pty'>
          <target type='isa-serial' port='0'>
            <model name='isa-serial'/>
          </target>
        </serial>
        <console type='pty'>
          <target type='serial' port='0'/>
        </console>
        <channel type='unix'>
          <target type='virtio' name='org.qemu.guest_agent.0'/>
        </channel>
        <graphics type='vnc' port='${toString cfg.vncPort}' autoport='no' listen='127.0.0.1'>
          <listen type='address' address='127.0.0.1'/>
        </graphics>
        <video>
          <model type='virtio' heads='1' primary='yes'/>
        </video>
        <memballoon model='virtio'/>
        <rng model='virtio'>
          <backend model='random'>/dev/urandom</backend>
        </rng>
      </devices>
    </domain>
  '';
in
{
  options.services.home-assistant-vm = {
    enable = lib.mkEnableOption "Home Assistant OS VM hosting";

    domainName = lib.mkOption {
      type = lib.types.str;
      default = "home-assistant";
      description = "Libvirt domain name for the Home Assistant VM.";
    };

    uuid = lib.mkOption {
      type = lib.types.str;
      default = "14a534cf-951b-4ea2-884e-9872cd0596a3";
      description = "Libvirt UUID for the Home Assistant VM.";
    };

    memoryKiB = lib.mkOption {
      type = lib.types.int;
      default = 8388608;
      description = "Memory in KiB allocated to the Home Assistant VM.";
    };

    vcpu = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Number of vCPUs allocated to the Home Assistant VM.";
    };

    diskImage = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/libvirt/images/haos-11.2-restored.qcow2";
      description = "Path to the disk image for the Home Assistant VM.";
    };

    nvramPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/libvirt/qemu/nvram/home-assistant_VARS.fd";
      description = "Path to the NVRAM file for the Home Assistant VM.";
    };

    macAddress = lib.mkOption {
      type = lib.types.str;
      default = "52:54:00:a0:a7:1b";
      description = "MAC address for the Home Assistant VM network interface.";
    };

    vncPort = lib.mkOption {
      type = lib.types.int;
      default = 5900;
      description = "VNC display port for the Home Assistant VM.";
    };

    domainXml = lib.mkOption {
      type = lib.types.path;
      default = defaultDomainXml;
      defaultText = lib.literalExpression ''pkgs.writeText "''${cfg.domainName}.xml" ...'';
      description = "Nix-managed libvirt domain XML.";
    };

    physicalInterface = lib.mkOption {
      type = lib.types.str;
      description = "Physical interface enslaved into the VM bridge.";
    };

    bridgeName = lib.mkOption {
      type = lib.types.str;
      default = "hass-br0";
      description = "Bridge name used by the Home Assistant VM.";
    };

    bridgeMac = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Stable MAC address for the host bridge, when required.";
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether libvirt should autostart the Home Assistant VM.";
    };
  };
}
