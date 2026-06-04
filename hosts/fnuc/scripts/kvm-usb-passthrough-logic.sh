# USB_DEVICES, CALLBACKS, VIRSH_DOMAIN and SLEEP_INTERVAL are injected
# by the Nix wrapper — do not define them here.

# NOTE: The type of the hostdev node changes depending on whether one or
# multiple devices are attached (object vs array). yq has no if-then-else
# for this, so we use the conditional-update trick instead:
#   https://mikefarah.gitbook.io/yq/usage/tips-and-tricks#logic-without-if-elif-else
list_attached_usb_devices() {
    local domain="$1"
    virsh dumpxml --domain "$domain" |
        yq --input-format xml --output-format json |
        jq -er '[
            .domain.devices |
            if (.hostdev | type == "array") then .hostdev[] else .hostdev end |
            select(.["+@type"] == "usb").source |
            {"vendor": .vendor["+@id"], "product": .product["+@id"]}
        ]'
}

device_is_attached() {
    list_attached_usb_devices "$1" |
        jq -e \
            --arg vendor "0x$2" \
            --arg product "0x$3" \
            '.[] | select(.vendor == $vendor and .product == $product)' \
            >/dev/null
}

device_connected_to_host() {
    local vendor="0x$1"
    local model="0x$2"
    lsusb -d "${vendor}:${model}" >/dev/null
}

check_devices() {
    local device vendor model rc=0

    for device in "${!USB_DEVICES[@]}"; do
        vendor="${USB_DEVICES[$device]%%:*}"
        model="${USB_DEVICES[$device]#*:}"

        echo "📻 Checking device: $device ($vendor:$model)" >&2

        if device_connected_to_host "$vendor" "$model"; then
            echo "✅ $device ($vendor:$model) is connected to host" >&2
        else
            echo "❌ $device ($vendor:$model) is NOT connected to host — skipping" >&2
            rc=1
            continue
        fi

        if device_is_attached "$VIRSH_DOMAIN" "$vendor" "$model"; then
            echo "✅ $device is attached to $VIRSH_DOMAIN" >&2
            continue
        fi

        echo "⚠️  $device is NOT attached — attaching now..." >&2

        if virt-hotplug --domain "$VIRSH_DOMAIN" attach "$vendor" "$model"; then
            echo "✅ $device is now attached to $VIRSH_DOMAIN" >&2

            local cb="${CALLBACKS[$device]:-}"
            if [[ -n "$cb" ]]; then
                echo "⚙️  Running callback for $device: $cb" >&2
                eval "$cb" || true
            fi
        else
            echo "❌ Failed to attach $device to $VIRSH_DOMAIN" >&2
            rc=1
        fi
    done

    return "$rc"
}

case "${1:-}" in
    loop | --loop | -l)
        while true; do
            check_devices || true
            echo "⌛ Checking again in ${SLEEP_INTERVAL}s..." >&2
            sleep "$SLEEP_INTERVAL"
        done
        ;;
    *)
        check_devices
        ;;
esac
