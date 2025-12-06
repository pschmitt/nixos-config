{
  inputs,
  lib,
  modulesPath,
  pkgs,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.hardware.nixosModules.gpd-pocket-4
    ./disko-config.nix

    ../../hardware/fprintd.nix
    ../../hardware/touchscreen.nix
  ];

  swapDevices = [
    {
      device = "/swapfile";
      size = 16384; # storage space is basically free nowadays
    }
  ];

  networking.useDHCP = lib.mkDefault true;

  # ethernet nic, for network initrd
  boot.initrd.availableKernelModules = [ "r8169" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  hardware = {
    highDpi = true;

    # Display rotation via IIO sensors
    sensor.iio.enable = lib.mkDefault true;
  };

  services.fprintd = {
    enable = true;
    package = pkgs.fprintd.override {
      libfprint = pkgs.libfprint-focaltech;
    };
  };

  environment.systemPackages = [

    (pkgs.writeShellScriptBin "gpd-fanctl" ''
      usage() {
        cat << EOF
      Usage: gpd-fanctl [auto|manual|off] [value]
        auto    → let EC/kernel manage fan
        manual  → set manual mode; requires [value] 0-255
        off     → disable control (fan full speed)
        *       → show current RPM
      EOF
      }

      HWMON_BASE=/sys/devices/platform/gpd_fan/hwmon
      HWMON_DIR=$(ls -d "$HWMON_BASE"/hwmon* 2>/dev/null | head -n1)

      if [ -z "$HWMON_DIR" ]
      then
        echo "gpd_fan hwmon device not found" >&2
        exit 2
      fi

      while [ -n "$*" ]
      do
        case "$1" in
          -h|--help|-\?)
            usage
            exit 0
            ;;
          -q|--quiet)
            QUIET=1
            shift
            ;;
          *)
            break
            ;;
        esac
      done

      ACTION="$1"

      case "$ACTION" in
        auto)
          echo 2 | sudo tee "''${HWMON_DIR}/pwm1_enable"
          ;;
        manual)
          if [ -z "$2" ] || [ "$2" -lt 0 ] || [ "$2" -gt 255 ]
          then
            echo "Need value 0-255" >&2
            exit 2
          fi
          VALUE="$2"
          echo 1 | sudo tee "''${HWMON_DIR}/pwm1_enable"
          echo "$VALUE" | sudo tee "''${HWMON_DIR}/pwm1"
          ;;
        off)
          echo 0 | sudo tee "''${HWMON_DIR}/pwm1_enable"
          ;;
        *)
          [ -z "$QUIET" ] && echo -n "Current RPM: "
          cat "$HWMON_DIR/fan1_input"
          ;;
      esac
    '')
  ];
}
