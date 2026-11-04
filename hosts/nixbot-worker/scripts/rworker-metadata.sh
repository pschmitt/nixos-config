#!/usr/bin/env bash
# Show what this worker is: its name, who created it and why, its expiry
# and lifetime, and the machine itself. Reads the boot-time snapshot
# (/run/rworker/metadata.json) and refreshes the server metadata from the
# OpenStack metadata service (expiry changes with `rworker extend`).

SNAPSHOT=/run/rworker/metadata.json

usage() {
  cat <<EOF
Usage: $(basename "$0") [-j|--json] [--initial]

Show this worker's metadata: name, kind, owner, creator (agent, PID,
session, topic, cwd), expiry and lifetime, boot time, system, CPUs, memory,
disk and NetBird IP.

  -j, --json   print JSON
  --initial    only the snapshot from boot ($SNAPSHOT),
               do not ask the metadata service for current values
EOF
}

# The metadata service URL; the boot test points it elsewhere through
# the kernel command line, like nixbot-worker-netbird-up does.
metadata_url() {
  local arg url="http://169.254.169.254/openstack/latest"
  for arg in $(< /proc/cmdline)
  do
    if [[ "$arg" == nixbot-worker.metadata=* ]]
    then
      url="${arg#nixbot-worker.metadata=}"
    fi
  done
  printf '%s\n' "$url"
}

# Current server metadata (null when the service does not answer).
live_meta() {
  curl -fsS --max-time 3 "$(metadata_url)/meta_data.json" 2>/dev/null \
    | jq -c '(.meta // {}) | del(.setup_key_id)' 2>/dev/null \
    || printf 'null\n'
}

# Facts about the machine right now.
host_facts() {
  local ip disk
  ip=$(ip -4 -o addr show dev wt0 2>/dev/null | awk '{ sub("/.*", "", $4); print $4; exit }')
  # The encrypted data partition (store upper layer, builds, /home).
  disk=$(df -B1 --output=size,avail /nix/.rw-store 2>/dev/null \
    | awk 'NR == 2 { printf "{\"size\": %s, \"avail\": %s}", $1, $2 }')
  jq -n \
    --arg hostname "$(uname -n)" \
    --arg ip "$ip" \
    --argjson cpus "$(nproc)" \
    --argjson mem "$(awk '/^MemTotal:/ { print $2 * 1024 }' /proc/meminfo)" \
    --argjson uptime "$(cut -d. -f1 /proc/uptime)" \
    --arg load "$(cut -d' ' -f1-3 /proc/loadavg)" \
    --argjson disk "${disk:-null}" \
    '{hostname: $hostname, netbird_ip: (if $ip == "" then null else $ip end),
      cpus: $cpus, memory_bytes: $mem, uptime_seconds: $uptime,
      load: $load, disk: $disk}'
}

collect() {
  local initial="$1" snapshot live
  if [[ -r "$SNAPSHOT" ]]
  then
    snapshot=$(< "$SNAPSHOT")
  else
    snapshot='{"source": "none"}'
  fi
  live=null
  if [[ -z "$initial" ]]
  then
    live=$(live_meta)
  fi
  jq -c --argjson live "$live" --argjson host "$(host_facts)" '
    . + (if $live then {source: "live", meta: $live} else {} end)
      + {host: $host}' <<< "$snapshot"
}

bold() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]
  then
    printf '\e[1m%s\e[0m' "$*"
  else
    printf '%s' "$*"
  fi
}

line() {
  if [[ -n "$2" && "$2" != - ]]
  then
    printf '%s %s\n' "$(bold "$(printf '%-14s' "$1:")")" "$2"
  fi
}

# "2026-11-04 14:13 (in 1h 59m)" for an epoch timestamp.
when() {
  local at="$1" delta
  if [[ -z "$at" || "$at" == 0 ]]
  then
    return 0
  fi
  at="${at%.*}"
  delta=$(( at - $(date +%s) ))
  if (( delta >= 0 ))
  then
    printf '%s (in %dh %dm)' "$(date -d "@$at" '+%F %H:%M')" \
      $(( delta / 3600 )) $(( delta % 3600 / 60 ))
  else
    delta=$(( -delta ))
    printf '%s (%dh %dm ago)' "$(date -d "@$at" '+%F %H:%M')" \
      $(( delta / 3600 )) $(( delta % 3600 / 60 ))
  fi
}

human() {
  local info="$1"
  local -a f
  mapfile -t f < <(jq -r '
    def s(v): (v // "-") | tostring;
    s(.name), s(.meta["nixbot-worker"]), s(.meta.owner), s(.meta.agent),
    s(.meta.agent_pid), s(.meta.agent_session), s(.meta.topic),
    s(.meta.cwd), s(.uuid), s(.availability_zone),
    (.meta.created_at // 0 | tostring), (.meta.expires_at // 0 | tostring),
    ((.meta.created_at // 0 | tonumber) + (.meta.max_lifetime // 0 | tonumber)
      | tostring),
    (.meta.last_active // 0 | tostring),
    s(.booted), s(.system), s(.host.netbird_ip), s(.host.cpus),
    (.host.memory_bytes // 0 | tostring), s(.host.load),
    (.host.disk.avail // 0 | tostring), (.host.disk.size // 0 | tostring),
    (.host.uptime_seconds // 0 | tostring), s(.source)' <<< "$info")
  local agent="${f[3]}"
  if [[ "${f[4]}" != - ]]
  then
    agent+=" (PID ${f[4]})"
  fi
  line Name "${f[0]}"
  line Kind "${f[1]}"
  line Owner "${f[2]}"
  if [[ "${f[3]}${f[6]}${f[7]}" != --- ]]
  then
    printf '%s\n' "$(bold Creator:)"
    line "  Agent" "$agent"
    line "  Session" "${f[5]}"
    line "  Topic" "${f[6]}"
    line "  Cwd" "${f[7]}"
  fi
  line UUID "${f[8]}"
  line Zone "${f[9]}"
  line Created "$(when "${f[10]}")"
  line Expires "$(when "${f[11]}")"
  if [[ "${f[11]}" != 0 ]] && (( ${f[11]%.*} < $(date +%s) ))
  then
    line Grace "expired: kept while in use, deleted after 1h idle (last seen in use: $(when "${f[13]}"))"
  fi
  if [[ "${f[12]}" != "${f[10]}" ]]
  then
    line "Max lifetime" "$(when "${f[12]}")"
  fi
  line Booted "${f[14]} (up $(( f[22] / 3600 ))h $(( f[22] % 3600 / 60 ))m)"
  line System "${f[15]}"
  line "NetBird IP" "${f[16]}"
  line CPUs "${f[17]} (load ${f[19]})"
  line Memory "$(( f[18] / 1024 / 1024 / 1024 )) GiB"
  if [[ "${f[21]}" != 0 ]]
  then
    line Disk "$(( f[20] / 1024 / 1024 / 1024 )) GiB free of $(( f[21] / 1024 / 1024 / 1024 )) GiB (encrypted)"
  fi
  if [[ "${f[23]}" != live ]]
  then
    line Source "${f[23]} (boot-time snapshot; current expiry may differ)"
  fi
}

main() {
  local json="" initial="" info
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      -j|--json)
        json=1
        ;;
      --initial)
        initial=1
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
    shift
  done
  info=$(collect "$initial") || return 1
  if [[ -n "$json" ]]
  then
    jq . <<< "$info"
  else
    human "$info"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
