{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.kvm-usb-passthrough;

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

  # Virt-hotplug helper script
  virtHotplug = pkgs.writeShellScriptBin "virt-hotplug" (builtins.readFile ./scripts/virt-hotplug.sh);

  mkBashAssocArray =
    name: attrs:
    let
      entries = lib.mapAttrsToList (k: v: "  [${k}]=\"${v}\"") attrs;
    in
    "declare -A ${name}=(\n${lib.concatStringsSep "\n" entries}\n)";

  ensurePassthrough = pkgs.writeShellApplication {
    name = "kvm-usb-ensure-passthrough";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.jq
      pkgs.libvirt
      pkgs.ripgrep
      pkgs.usbutils
      pkgs.yq-go
      virtHotplug
    ];
    excludeShellChecks = [ "SC2294" ];
    text = ''
      ${mkBashAssocArray "USB_DEVICES" cfg.devices}
      ${mkBashAssocArray "CALLBACKS" cfg.callbacks}

      VIRSH_DOMAIN="''${VIRSH_DOMAIN:-${cfg.domain}}"
      SLEEP_INTERVAL="''${SLEEP_INTERVAL:-${toString cfg.checkInterval}}"

      export LIBVIRT_DEFAULT_URI="''${LIBVIRT_DEFAULT_URI:-qemu:///system}"

      ${builtins.readFile ./scripts/kvm-usb-passthrough-logic.sh}
    '';
  };

  kvmUsbReplug = pkgs.writeShellApplication {
    name = "kvm-usb-replug";
    runtimeInputs = [
      pkgs.fzf
      pkgs.libvirt
      pkgs.usbutils
      virtHotplug
    ];
    text = ''
      usage() {
        echo "Usage: $0 [-h|--help] [-d|--domain DOMAIN] [vendor:product...]" >&2
        echo "With no device IDs and an interactive terminal, an fzf picker is shown." >&2
        exit 2
      }

      help() {
        echo "Usage: $0 [-h|--help] [-d|--domain DOMAIN] [vendor:product...]"
        echo ""
        echo "Re-plug USB device(s) passed through to the ${cfg.domain} KVM domain."
        echo "With no device IDs and an interactive terminal, an fzf picker is shown."
        echo ""
        echo "Options:"
        echo "  -h, --help            Show this help"
        echo "  -d, --domain DOMAIN   KVM domain name (default: ${cfg.domain})"
      }

      VIRSH_DOMAIN="''${VIRSH_DOMAIN:-${cfg.domain}}"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h | --help)
            help
            exit 0
            ;;
          -d | --domain)
            VIRSH_DOMAIN="$2"
            shift 2
            ;;
          --)
            shift
            break
            ;;
          -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
          *)
            break
            ;;
        esac
      done

      if [[ $# -eq 0 ]]; then
        if [[ -t 0 ]]; then
          mapfile -t args < <(
            lsusb \
              | awk '{id=$6; name=substr($0, index($0,$7)); printf "%-13s  %s\n", id, name}' \
              | fzf --multi \
                --prompt="Select USB devices to replug > " \
                --preview='lsusb -v -d {1} 2>/dev/null' \
                --preview-window='right:60%:wrap' \
                | awk '{print $1}' \
              || true
          )
          [[ ''${#args[@]} -eq 0 ]] && exit 0
          set -- "''${args[@]}"
        else
          usage
        fi
      fi

      for usb_id in "$@"; do
        virt-hotplug --force --domain "$VIRSH_DOMAIN" attach "$usb_id"
      done
    '';
  };

  mkReplugScript =
    name: id:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ kvmUsbReplug ];
      text = ''
        case "''${1:-}" in
          -h | --help)
            echo "Usage: $0 [-h|--help] [-d|--domain DOMAIN]"
            echo ""
            echo "Re-plug USB device ${id} passed through to the ${cfg.domain} KVM domain."
            exit 0
            ;;
        esac
        exec kvm-usb-replug "$@" ${id}
      '';
    };

  replugCoral = pkgs.writeShellApplication {
    name = "kvm-usb-replug-coral";
    runtimeInputs = [ kvmUsbReplug ];
    text = ''
      case "''${1:-}" in
        -h | --help)
          echo "Usage: $0 [-h|--help] [-d|--domain DOMAIN]"
          echo ""
          echo "Re-plug Google Coral USB device (tries both USB IDs: 1a6e:089a and 18d1:9302)."
          exit 0
          ;;
      esac
      kvm-usb-replug "$@" 1a6e:089a || true
      kvm-usb-replug "$@" 18d1:9302 || true
    '';
  };

  replugUps = mkReplugScript "kvm-usb-replug-ups" "0463:ffff";
  replugSonoffDongle = mkReplugScript "kvm-usb-replug-sonoff-dongle" "1a86:55d4";
  replugZbt2 = mkReplugScript "kvm-usb-replug-zbt2" "303a:831a";
  replugZwa2 = mkReplugScript "kvm-usb-replug-zwa2" "303a:4001";
  replugAisSdr = mkReplugScript "kvm-usb-replug-ais-sdr" "0bda:2838";
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

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      virtHotplug
      ensurePassthrough
      kvmUsbReplug
      replugCoral
      replugUps
      replugSonoffDongle
      replugZbt2
      replugZwa2
      replugAisSdr
    ];

    systemd.services.kvm-usb-passthrough = {
      description = "Home Assistant KVM USB Passthrough Watchdog";
      wantedBy = [ "multi-user.target" ];
      after = [ "libvirtd.service" ];
      wants = [ "libvirtd.service" ];
      serviceConfig = {
        ExecStart = "${ensurePassthrough}/bin/kvm-usb-ensure-passthrough --loop";
        Restart = "always";
        RestartSec = "30s";
      };
    };
  };
}
