# Boot the rworker disk image twice in QEMU (UEFI) and check, from
# the outside, that each boot encrypts a fresh data partition.
# usage: boot-test.sh IMAGE OVMF_CODE OVMF_VARS OUT

image="$1"
ovmf_code="$2"
ovmf_vars="$3"
out="$4"
# Answers the OpenStack metadata service (169.254.169.254) inside QEMU.
metadata_responder="$5"

mkdir -p "$out"
work=$(mktemp -d)
disk="${work}/disk.raw"
vars="${work}/vars.fd"

cp --no-preserve=mode "$image" "$disk"
cp --no-preserve=mode "$ovmf_vars" "$vars"

# QEMU's guestfwd cannot use 169.254.169.254: point the worker at the fake
# metadata service on 10.0.2.100 (this copy of the disk only).
esp_offset=$(( $(sfdisk --json "$disk" | jq -er '.partitiontable.partitions[0].start') * 512 ))
entry=::/loader/entries/rworker.conf
mtype -i "${disk}@@${esp_offset}" "$entry" \
  | sed 's|^options |options nixbot-worker.metadata=http://10.0.2.100/openstack/latest |' \
  > "${work}/entry.conf"
mcopy -o -i "${disk}@@${esp_offset}" "${work}/entry.conf" "$entry"
# Room for the data partition repart adds at boot.
truncate -s 6G "$disk"

accel=tcg
if [[ -w /dev/kvm ]]
then
  accel=kvm
fi

luks_header() {
  # Second partition: the one repart created (the first is the ESP).
  local start
  start=$(sfdisk --json "$disk" | jq -er '.partitiontable.partitions[1].start')
  dd if="$disk" bs=512 skip="$start" count=8 status=none
}

boot() {
  local n=$1 log="${out}/serial-$1.log" pid
  : > "$log"
  qemu-system-x86_64 \
    -machine "q35,accel=${accel}" -m "${NIXBOT_TEST_MEMORY_MIB:-3072}" -smp 2 \
    -drive "if=pflash,format=raw,readonly=on,file=${ovmf_code}" \
    -drive "if=pflash,format=raw,file=${vars}" \
    -drive "file=${disk},format=raw,if=virtio,cache=writethrough" \
    -nic "user,model=virtio,guestfwd=tcp:10.0.2.100:80-cmd:${metadata_responder}" \
    -display none -monitor none -serial "file:${log}" &
  pid=$!

  local deadline=$((SECONDS + 900))
  until grep -q '^NIXBOT-WORKER-HOSTKEY ' "$log"
  do
    if (( SECONDS > deadline )) || ! kill -0 "$pid" 2>/dev/null \
      || grep -a -q -E 'Freezing execution|emergency mode' "$log"
    then
      echo "boot ${n}: no host key on the serial console" >&2
      sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$log" | tr -d '\r' \
        | grep -a -i -E 'repart|cryptsetup|workerdata|fail|error|emergency' >&2 || true
      kill "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 2
  done
  # rworker-netbird-up got its name and wrote the metadata (joining
  # NetBird itself cannot work without internet).
  local named=""
  for _ in $(seq 1 60)
  do
    if grep -a -q 'rworker: named test-worker' "$log"
    then
      named=1
      break
    fi
    sleep 2
  done
  if [[ -z "$named" ]]
  then
    echo "boot ${n}: worker did not take its name from the metadata service" >&2
    sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$log" | tr -d '\r' \
      | grep -a -i -E 'netbird-up|hostname|metadata|fail' >&2 || true
    kill "$pid" 2>/dev/null || true
    return 1
  fi

  kill "$pid"
  wait "$pid" || true

  if [[ "$(luks_header | head -c 6 | od -An -tx1 | tr -d ' \n')" != "4c554b53babe" ]]
  then
    echo "boot ${n}: data partition has no LUKS header" >&2
    return 1
  fi
  grep -a -o '^NIXBOT-WORKER-HOSTKEY .*' "$log" | head -1 > "${out}/hostkey-${n}"
  # LUKS2 UUID: 40 bytes at offset 168 of the header.
  luks_header | dd bs=1 skip=168 count=40 status=none | tr -d '\0' > "${out}/luks-uuid-${n}"
  echo "boot ${n}: $(cat "${out}/luks-uuid-${n}") $(cut -d' ' -f3 "${out}/hostkey-${n}")"
}

boot 1
boot 2

if cmp -s "${out}/luks-uuid-1" "${out}/luks-uuid-2"
then
  echo "the second boot reused the first boot's LUKS volume" >&2
  exit 1
fi
if cmp -s "${out}/hostkey-1" "${out}/hostkey-2"
then
  echo "the second boot reused the first boot's host key" >&2
  exit 1
fi
echo "ok: fresh encrypted data partition and host key on every boot"
