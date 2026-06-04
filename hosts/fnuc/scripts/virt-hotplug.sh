#!/usr/bin/bash

usage() {
  echo "Usage: $0 [--dry-run] [--force] [--domain DOMAIN] <add|remove> VENDOR_ID MODEL_ID"
}

device_is_attached() {
  virsh dumpxml "$VIRSH_DOMAIN" | \
    tr -d '[:space:]' | \
    rg -q "<vendorid='0x${VENDOR_ID}'/><productid='0x${MODEL_ID}'/>"
}

device_xml() {
  local vendor="$1"
  local product="$2"

cat <<EOT
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source>
    <vendor id='0x${vendor}'/>
    <product id='0x${product}'/>
  </source>
</hostdev>
EOT
}

attach_device() {
  if [[ -n $DRY_RUN ]]
  then
    echo "Dry run: would attach USB device $VENDOR_ID:$MODEL_ID to domain $VIRSH_DOMAIN"
    return 0
  fi

  if device_is_attached && [[ -z $FORCE ]]
  then
    echo "USB device $VENDOR_ID:$MODEL_ID is already attached to domain $VIRSH_DOMAIN" >&2
    return 0
  fi

  if [[ -n $FORCE ]]
  then
    echo "Force reattaching USB device: $VENDOR_ID:$MODEL_ID on domain: $VIRSH_DOMAIN" >&2
    virsh detach-device --live "$VIRSH_DOMAIN" /dev/stdin <<< "$XML" || true
  fi

  echo "Attaching USB device: $VENDOR_ID:$MODEL_ID to domain: $VIRSH_DOMAIN" >&2
  virsh attach-device --live "$VIRSH_DOMAIN" /dev/stdin <<< "$XML"
}

detach_device() {
  if [[ -n $DRY_RUN ]]
  then
    echo "Dry run: would detach USB device $VENDOR_ID:$MODEL_ID from domain $VIRSH_DOMAIN"
    return 0
  fi

  if ! device_is_attached
  then
    echo "USB device $VENDOR_ID:$MODEL_ID is not attached to domain $VIRSH_DOMAIN" >&2
    return 0
  fi

  echo "Removing USB device: $VENDOR_ID:$MODEL_ID from domain: $VIRSH_DOMAIN" >&2
  virsh detach-device --live "$VIRSH_DOMAIN" /dev/stdin <<< "$XML"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  logger "virt-hotplug: $ACTION $VENDOR_ID $MODEL_ID"

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help|help)
        usage
        exit 0
        ;;
      -d|--domain)
        VIRSH_DOMAIN="$2"
        shift 2
        ;;
      -k|--dryrun|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -f|--force)
        FORCE=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  DRY_RUN=${DRY_RUN:-}
  FORCE=${FORCE:-}
  ACTION="$1"
  VENDOR_ID="$2"
  MODEL_ID="$3"
  VIRSH_DOMAIN="${VIRSH_DOMAIN:-home-assistant}"  # default domain

  if [[ -z "$ACTION" ]]
  then
    usage >&2
    exit 2
  fi

  if [[ -n $VENDOR_ID && $VENDOR_ID == *:* ]]
  then
    # Validate and split abcd:1234
    if [[ $VENDOR_ID =~ ^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})$ ]]
    then
      VENDOR_ID="${BASH_REMATCH[1],,}"
      MODEL_ID="${BASH_REMATCH[2],,}"
    else
      echo "Invalid USB ID format. Expected: abcd:1234" >&2
      exit 2
    fi
  fi

  if [[ -z "$VENDOR_ID" ]]
  then
    {
      echo "Missing VENDOR_ID"
      usage
    } >&2
    exit 2
  fi

  if [[ -z "$MODEL_ID" ]]
  then
    {
      echo "Missing MODEL_ID"
      usage
    } >&2
    exit 2
  fi

  XML="$(device_xml "$VENDOR_ID" "$MODEL_ID")"

  case "$ACTION" in
    attach|add)
      attach_device
      ;;
    detach|remove|rm|del)
      detach_device
      ;;
    # TODO detach and reattach currently attached usb devices
    # reattach)
    #   ;;
    *)
      {
        echo "Unknown ACTION: $ACTION"
        usage
      } >&2
      exit 2
      ;;
  esac
fi
