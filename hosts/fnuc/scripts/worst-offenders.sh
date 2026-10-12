#!/usr/bin/env bash
# Rescue-shell counterpart of the zsh ps::worst-offenders: the top CPU and
# memory consumers (merged, deduped, sorted by CPU), plus the systemd unit
# each one runs in. Only needs procps + coreutils + gawk, no jq or zsh.
# CPU is sampled over DELAY seconds by top, not ps' lifetime average.

usage() {
  cat <<EOF
Usage: $(basename "$0") [-n COUNT] [-d DELAY] [-m|--mem] [-a|--args]

  -n, --count COUNT  Number of processes to show (default: 10)
  -d, --delay DELAY  CPU sampling interval in seconds (default: 1)
  -m, --mem          Sort by memory instead of CPU
  -a, --args         Show the full command line instead of the name
  -h, --help         Show this help
EOF
}

print_summary() {
  local resource

  printf 'load: %s\n' "$(cut -d ' ' -f 1-4 /proc/loadavg)"
  free -h | awk 'NR > 1 { printf "%-5s total %s, used %s, avail %s\n", $1, $2, $3, $NF }'

  for resource in cpu memory io
  do
    if [[ -r "/proc/pressure/${resource}" ]]
    then
      awk -v r="$resource" '
        { printf "psi %-6s %-4s %s %s\n", r, $1, $2, $3 }
      ' "/proc/pressure/${resource}"
    fi
  done

  awk '
    /^procs_running/ { r = $2 }
    /^procs_blocked/ { b = $2 }
    END { printf "procs: %s running, %s blocked (D)\n\n", r, b }
  ' /proc/stat
}

# Second top iteration only: the first one reports lifetime averages.
# Output: pid user state cpu mem res
sample_top() {
  local delay="$1"

  top -b -n 2 -d "$delay" -w 512 -e m | awk '
    /^ *PID +USER/ {
      block++
      next
    }
    block == 2 && NF >= 12 {
      print $1, $2, $8, $9, $10, $6
    }
  '
}

pick_offenders() {
  local count="$1"
  local sort_key="$2"
  local samples

  samples=$(cat)

  {
    sort -k4,4 -g -r <<< "$samples" | head -n "$count"
    sort -k5,5 -g -r <<< "$samples" | head -n "$count"
  } | awk '!seen[$1]++' | sort -k"$sort_key","$sort_key" -g -r | head -n "$count"
}

unit_of() {
  local pid="$1"
  local cgroup leaf

  # The process may be gone by now
  cgroup=$(cut -d : -f 3 "/proc/${pid}/cgroup" 2>/dev/null) || true
  leaf="${cgroup##*/}"

  # Leaves like qemu's libvirt/emulator say little: walk up to the
  # nearest systemd unit (anything with a .scope/.service suffix).
  while [[ -n "$cgroup" && "${cgroup##*/}" != *.* ]]
  do
    cgroup="${cgroup%/*}"
  done

  if [[ -n "$cgroup" && "${cgroup##*/}" != "$leaf" ]]
  then
    leaf="${cgroup##*/}"
  fi

  printf '%s' "${leaf:--}"
}

command_of() {
  local pid="$1"
  local full_args="$2"
  local cmd

  if [[ -n "$full_args" ]]
  then
    cmd=$( (tr '\0' ' ' < "/proc/${pid}/cmdline") 2>/dev/null) || true
  fi

  if [[ -z "${cmd:-}" ]]
  then
    cmd=$(cat "/proc/${pid}/comm" 2>/dev/null) || true
  fi

  printf '%s' "${cmd:-?}"
}

print_offenders() {
  local full_args="$1"
  local pid user state cpu mem res

  printf '%-8s %-10s %-1s %6s %5s %8s  %-40s %s\n' \
    PID USER S CPU% MEM% RES UNIT COMMAND

  while read -r pid user state cpu mem res
  do
    printf '%-8s %-10.10s %-1s %6s %5s %8s  %-40.40s %.120s\n' \
      "$pid" "$user" "$state" "$cpu" "$mem" "$res" \
      "$(unit_of "$pid")" "$(command_of "$pid" "$full_args")"
  done
}

main() {
  local count=10
  local delay=1
  local sort_key=4
  local full_args

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      -n|--count)
        count="${2:-}"
        shift 2
        ;;
      -d|--delay)
        delay="${2:-}"
        shift 2
        ;;
      -m|--mem)
        sort_key=5
        shift
        ;;
      -a|--args)
        full_args=1
        shift
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  if [[ ! "$count" =~ ^[0-9]+$ ]]
  then
    printf 'Invalid count: %s\n' "$count" >&2
    usage >&2
    return 2
  fi

  print_summary
  sample_top "$delay" | pick_offenders "$count" "$sort_key" | print_offenders "${full_args:-}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
