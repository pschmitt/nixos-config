#!/usr/bin/env bash
# Log the cgroups holding the most memory (RAM + swap), one line each, so
# the journal keeps a history of who held what when memory runs out.
# Parents include their children: a slice and its units both show up.
# Read back with: journalctl -t memory-snapshot

usage() {
  cat <<EOF
Usage: $(basename "$0") [-n COUNT]

  -n, --count COUNT  Number of cgroups to log (default: 15)
  -h, --help         Show this help
EOF
}

print_totals() {
  awk '
    /^MemTotal:/ { total = $2 }
    /^MemAvailable:/ { avail = $2 }
    /^SwapTotal:/ { swap_total = $2 }
    /^SwapFree:/ { swap_free = $2 }
    END {
      printf "total: ram used %.1fG of %.1fG, swap used %.1fG of %.1fG\n",
        (total - avail) / 1048576, total / 1048576,
        (swap_total - swap_free) / 1048576, swap_total / 1048576
    }
  ' /proc/meminfo
}

# Output: ram_bytes swap_bytes cgroup_path
list_cgroups() {
  local dir ram swap

  while read -r dir
  do
    ram=$(cat "${dir}/memory.current" 2>/dev/null) || continue
    swap=$(cat "${dir}/memory.swap.current" 2>/dev/null) || swap=0
    printf '%s %s %s\n' "$ram" "$swap" "${dir#/sys/fs/cgroup/}"
  done < <(find /sys/fs/cgroup -mindepth 1 -maxdepth 6 -type d -name '*.*')
}

print_top() {
  local count="$1"

  # awk does the cutoff and reads everything: head would SIGPIPE sort,
  # which fails the pipeline under pipefail.
  list_cgroups | awk '{ print $1 + $2, $0 }' | sort -k1,1 -g -r | awk -v n="$count" '
    NR <= n {
      printf "%6.2fG ram %6.2fG swap  %s\n", $2 / 1073741824, $3 / 1073741824, $4
    }
  '
}

main() {
  local count=15

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

  print_totals
  print_top "$count"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
