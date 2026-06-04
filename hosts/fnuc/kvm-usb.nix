{ pkgs, ... }:
let
  # Core virsh hotplug helper — vendored from ~/devel/kvm/usb/virt-hotplug.sh.
  # Uses `sudo virsh` which must be in sudo's secure_path on fnuc.
  virtHotplug = pkgs.writeShellScriptBin "virt-hotplug" (builtins.readFile ./scripts/virt-hotplug.sh);

  # Generic replug: kvm-usb-replug [-d DOMAIN] [vendor:product...]
  # With no device IDs and a TTY: interactive fzf picker from lsusb output.
  kvmUsbReplug = pkgs.writeShellApplication {
    name = "kvm-usb-replug";
    runtimeInputs = [
      pkgs.fzf
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
        echo "Re-plug USB device(s) passed through to the home-assistant KVM domain on fnuc."
        echo "With no device IDs and an interactive terminal, an fzf picker is shown."
        echo ""
        echo "Options:"
        echo "  -h, --help            Show this help"
        echo "  -d, --domain DOMAIN   KVM domain name (default: home-assistant)"
        echo ""
        echo "Examples:"
        echo "  $0                              # interactive fzf picker"
        echo "  $0 303a:4001                    # replug ZWA-2"
        echo "  $0 1a6e:089a 18d1:9302          # replug both coral IDs"
        echo "  $0 --domain my-vm 303a:4001     # replug in a different KVM domain"
      }

      VIRSH_DOMAIN="''${VIRSH_DOMAIN:-home-assistant}"

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
            echo "Re-plug USB device ${id} passed through to the home-assistant KVM domain on fnuc."
            echo ""
            echo "Options:"
            echo "  -h, --help            Show this help"
            echo "  -d, --domain DOMAIN   KVM domain name (default: home-assistant)"
            exit 0
            ;;
        esac
        exec kvm-usb-replug "$@" ${id}
      '';
    };

  # Google Coral changes USB ID depending on firmware state; try both
  replugCoral = pkgs.writeShellApplication {
    name = "kvm-usb-replug-coral";
    runtimeInputs = [ kvmUsbReplug ];
    text = ''
      case "''${1:-}" in
        -h | --help)
          echo "Usage: $0 [-h|--help] [-d|--domain DOMAIN]"
          echo ""
          echo "Re-plug Google Coral USB device (tries both USB IDs: 1a6e:089a and 18d1:9302)."
          echo "The device changes its USB ID depending on firmware state."
          echo ""
          echo "Options:"
          echo "  -h, --help            Show this help"
          echo "  -d, --domain DOMAIN   KVM domain name (default: home-assistant)"
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
in
{
  home.packages = [
    virtHotplug
    kvmUsbReplug
    replugCoral
    replugUps
    replugSonoffDongle
    replugZbt2
    replugZwa2
  ];
}
