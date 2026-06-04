{ lib, pkgs, ... }:
let
  # ---------------------------------------------------------------------------
  # USB device registry
  # Edit here to add/remove devices — no need to touch any shell script.
  # ---------------------------------------------------------------------------
  virshDomain = "home-assistant";
  checkInterval = 10; # seconds between passthrough checks

  usbDevices = {
    eaton-ups = "0463:ffff";
    # Google Coral changes USB ID depending on firmware state:
    # https://github.com/google-coral/edgetpu/issues/536
    google-coral-1 = "1a6e:089a";
    google-coral-2 = "18d1:9302";
    # Home Assistant Connect ZBT-2 (Zigbee)
    zbt-2 = "303a:831a";
    # Home Assistant Connect ZWA-2 (Z-Wave)
    zwa-2 = "303a:4001";
    # Sonoff Zigbee 3.0 USB Dongle Plus-E (running Thread firmware)
    zbdongle-e = "1a86:55d4";
    # Everspring SA413-1 Z-Wave Plus dongle
    zwave-stick = "0658:0200";
  };

  # Callbacks run after a device is successfully (re-)attached.
  # Keys must match a key in usbDevices exactly.
  # Example: callbacks = { zbdongle-e = "zhj hass::reload-integration sms"; };
  callbacks = { };

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Prerequisite: pschmitt must be in the 'libvirt' group so virsh works
  # without sudo.  Run once on fnuc:
  #   sudo usermod -aG libvirt pschmitt
  # Also enable lingering so the user service survives without an active
  # login session:
  #   loginctl enable-linger pschmitt
  virtHotplug = pkgs.writeShellScriptBin "virt-hotplug" (builtins.readFile ./scripts/virt-hotplug.sh);

  # Generates a bash `declare -A name=( [key]="val" ... )` block.
  mkBashAssocArray =
    name: attrs:
    let
      entries = lib.mapAttrsToList (k: v: "  [${k}]=\"${v}\"") attrs;
    in
    "declare -A ${name}=(\n${lib.concatStringsSep "\n" entries}\n)";

  # ---------------------------------------------------------------------------
  # kvm-usb-ensure-passthrough
  # Checks that every device in usbDevices is connected to the host and
  # attached to the KVM domain; re-attaches any that are missing.
  # ---------------------------------------------------------------------------
  ensurePassthrough = pkgs.writeShellApplication {
    name = "kvm-usb-ensure-passthrough";
    runtimeInputs = [
      pkgs.jq
      pkgs.usbutils
      pkgs.yq-go
      virtHotplug
    ];
    # SC2294: eval is intentional for user-supplied callback strings
    excludeShellChecks = [ "SC2294" ];
    text = ''
      # --- generated from kvm-usb.nix — edit there, not here ----------------
      ${mkBashAssocArray "USB_DEVICES" usbDevices}

      ${mkBashAssocArray "CALLBACKS" callbacks}

      VIRSH_DOMAIN="''${VIRSH_DOMAIN:-${virshDomain}}"
      SLEEP_INTERVAL="''${SLEEP_INTERVAL:-${toString checkInterval}}"

      # Must be exported so every virsh call (including direct ones in
      # list_attached_usb_devices) hits the system daemon, not the user
      # session daemon (qemu:///session) that would be the default for a
      # user service.
      export LIBVIRT_DEFAULT_URI="''${LIBVIRT_DEFAULT_URI:-qemu:///system}"
      # -----------------------------------------------------------------------

      ${builtins.readFile ./scripts/kvm-usb-passthrough-logic.sh}
    '';
  };

  # ---------------------------------------------------------------------------
  # Generic replug: kvm-usb-replug [-d DOMAIN] [vendor:product...]
  # With no device IDs and a TTY: interactive fzf picker from lsusb output.
  # ---------------------------------------------------------------------------
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
        echo "  -d, --domain DOMAIN   KVM domain name (default: ${virshDomain})"
        echo ""
        echo "Examples:"
        echo "  $0                              # interactive fzf picker"
        echo "  $0 303a:4001                    # replug ZWA-2"
        echo "  $0 1a6e:089a 18d1:9302          # replug both coral IDs"
        echo "  $0 --domain my-vm 303a:4001     # replug in a different KVM domain"
      }

      VIRSH_DOMAIN="''${VIRSH_DOMAIN:-${virshDomain}}"

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
            echo "Re-plug USB device ${id} passed through to the ${virshDomain} KVM domain on fnuc."
            echo ""
            echo "Options:"
            echo "  -h, --help            Show this help"
            echo "  -d, --domain DOMAIN   KVM domain name (default: ${virshDomain})"
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
          echo "  -d, --domain DOMAIN   KVM domain name (default: ${virshDomain})"
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
    ensurePassthrough
    kvmUsbReplug
    replugCoral
    replugUps
    replugSonoffDongle
    replugZbt2
    replugZwa2
  ];

  # Systemd user service — replaces /etc/systemd/system/home-assistant-usb-passthrough.service.
  # Requires:
  #   sudo usermod -aG libvirt pschmitt   (virsh without sudo)
  #   loginctl enable-linger pschmitt     (service survives without active session)
  systemd.user.services.kvm-usb-passthrough = {
    Unit = {
      Description = "Home Assistant KVM USB Passthrough";
      After = [ "default.target" ];
    };
    Service = {
      ExecStart = "${ensurePassthrough}/bin/kvm-usb-ensure-passthrough --loop";
      Restart = "always";
      RestartSec = "30s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
