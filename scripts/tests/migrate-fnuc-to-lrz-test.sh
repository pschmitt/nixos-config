#!/usr/bin/env bash

# Each scenario runs in a fresh bash process, outside an if/! condition: testing
# functions in a conditional would disable the production script's errexit.
set -euo pipefail

usage() {
  printf 'Usage: %s [--help]\n' "$(basename "$0")"
}

define_mocks() {
  record() {
    printf '%s\n' "$*" >> "${TEST_TRACE}"
  }

  ssh() {
    local command="${*: -1}"
    local unit="${command##* }"
    record "ssh ${command}"
    case "$command" in
      *'domstate home-assistant')
        [[ "$scenario" != ha-dest-query-fails ]] || return 255
        case "$scenario" in
          ha-dest-running) printf 'running\n' ;;
          ha-dest-paused) printf 'paused\n' ;;
          *) printf 'shut off\n' ;;
        esac
        ;;
      'systemctl show --property=ActiveState --value '*)
        if [[ "$scenario" == srv-inactive && "$unit" == smokeping.service ]]
        then
          printf 'inactive\n'
        else
          printf 'active\n'
        fi
        ;;
      'sudo -n systemctl stop '*)
        if [[ "$scenario" == srv-stop-fails && "$unit" == smokeping.service ]]
        then
          return 42
        fi
        ;;
      'sudo -n systemctl start '*)
        if [[ "$scenario" == srv-start-fails && "$unit" == syslog-ng.service ]]
        then
          return 43
        fi
        ;;
      'sudo -n mkdir -p '*) ;;
      'sudo -n tee '*)
        # Consume the pipeline so a mocked dumpxml cannot fail with SIGPIPE.
        while IFS= read -r _line
        do
          :
        done
        ;;
      'sudo -n rm -- '*) ;;
      *)
        record "UNEXPECTED ssh ${command}"
        return 99
        ;;
    esac
  }

  source_virsh() {
    record "virsh $*"
    case "$1" in
      domstate)
        case "$scenario" in
          ha-source-query-fails) return 44 ;;
          ha-source-paused) printf 'paused\n' ;;
          ha-source-unknown) printf 'unknown\n' ;;
          ha-off|ha-dry-off) printf 'shut off\n' ;;
          *) printf 'running\n' ;;
        esac
        ;;
      dumpxml) printf '<domain/>\n' ;;
      snapshot-create-as)
        mock_phase=snapshot
        [[ "$scenario" != ha-snapshot-fails ]] || return 45
        ;;
      blockcommit)
        [[ "$scenario" != ha-commit-fails ]] || return 46
        mock_phase=pivot
        ;;
      *)
        record "UNEXPECTED virsh $*"
        return 99
        ;;
    esac
  }

  source_vm_disk() {
    record "disk ${mock_phase} ${*:-live}"
    local disk="$base"
    case "${mock_phase}" in
      initial)
        [[ "$scenario" != ha-disk-query-fails ]] || return 47
        if [[ "$scenario" == ha-live-overlay && $# -eq 0 ]] ||
          [[ "$scenario" == ha-inactive-overlay && "${1:-}" == --inactive ]]
        then
          disk="$overlay"
        fi
        ;;
      snapshot)
        if [[ "$scenario" != ha-snapshot-no-switch ]]
        then
          disk="$overlay"
        fi
        ;;
      pivot)
        if [[ "$scenario" == ha-pivot-live-overlay && $# -eq 0 ]] ||
          [[ "$scenario" == ha-pivot-inactive-overlay && "${1:-}" == --inactive ]]
        then
          disk="$overlay"
        fi
        ;;
    esac
    printf '%s\n' "$disk"
  }

  run_src_rsync() {
    record "rsync $* flags=${RSYNC_FLAGS[*]}"
    case "$scenario" in
      srv-copy-fails|ha-copy-fails) return 48 ;;
      ha-nvram-fails)
        [[ "$1" != *VARS.fd ]] || return 49
        ;;
      srv-term|ha-term)
        kill -TERM "$BASHPID"
        ;;
    esac
  }
}

run_scenario() {
  local scenario="$1"
  local script="$2"
  local base=/var/lib/libvirt/images/haos-11.2-restored.qcow2
  local overlay=/var/lib/libvirt/images/haos-presync-overlay.qcow2
  local mock_phase=initial
  # The production parser still runs on source; never give it harness arguments.
  set --
  # shellcheck source=/dev/null
  source "$script"
  define_mocks
  case "$scenario" in
    *dry*)
      DRY_RUN=1
      RSYNC_FLAGS+=(-n)
      ;;
  esac
  case "$scenario" in
    srv-*) migrate_srv ;;
    ha-*) migrate_ha_vm ;;
    *) return 2 ;;
  esac
}

require_trace() {
  if ! grep -Fq -- "$1" "$TEST_TRACE"
  then
    printf 'Missing trace: %s\n' "$1" >&2
    return 1
  fi
}

reject_trace() {
  if grep -Fq -- "$1" "$TEST_TRACE"
  then
    printf 'Unexpected trace: %s\n' "$1" >&2
    return 1
  fi
}

check_scenario() {
  local scenario="$1" status="$2"
  local expected=1
  case "$scenario" in
    srv-ok|srv-inactive|srv-dry|ha-ok|ha-off|ha-dry-running|ha-dry-off)
      expected=0
      ;;
  esac
  if [[ "$expected" -eq 0 && "$status" -ne 0 ]] ||
    [[ "$expected" -ne 0 && "$status" -eq 0 ]]
  then
    printf 'Unexpected exit status %s (expected success=%s)\n' "$status" "$((1 - expected))" >&2
    return 1
  fi
  reject_trace UNEXPECTED || return
  case "$scenario" in
    srv-dry|ha-dry-running|ha-dry-off)
      reject_trace 'sudo -n mkdir' || return
      reject_trace 'systemctl stop' || return
      reject_trace 'systemctl start' || return
      reject_trace 'snapshot-create-as' || return
      reject_trace 'blockcommit' || return
      reject_trace 'sudo -n rm' || return
      reject_trace 'sudo -n tee' || return
      if [[ "$scenario" != ha-dry-running ]]
      then
        require_trace ' -n' || return
      fi
      ;;
    srv-*)
      require_trace 'systemctl start syslog-ng.service' || return
      if [[ "$scenario" == srv-inactive ]]
      then
        reject_trace 'systemctl stop smokeping.service' || return
        reject_trace 'systemctl start smokeping.service' || return
      else
        require_trace 'systemctl start smokeping.service' || return
      fi
      if [[ "$scenario" == srv-stop-fails ]]
      then
        reject_trace 'rsync ' || return
        reject_trace 'systemctl start docker-ftpd.service' || return
      else
        require_trace 'rsync /srv/' || return
        require_trace 'systemctl start docker-ftpd.service' || return
      fi
      if [[ "$scenario" == srv-term ]]
      then
        [[ "$status" -eq 143 ]] || return 1
      fi
      ;;
    ha-dest-*|ha-live-overlay|ha-inactive-overlay|ha-disk-query-fails)
      reject_trace 'rsync ' || return
      reject_trace 'sudo -n mkdir' || return
      reject_trace 'snapshot-create-as' || return
      ;;
    ha-source-*)
      reject_trace 'rsync ' || return
      reject_trace 'snapshot-create-as' || return
      ;;
    ha-off)
      require_trace 'rsync /var/lib/libvirt/images/' || return
      require_trace 'rsync /var/lib/libvirt/qemu/nvram/' || return
      reject_trace 'snapshot-create-as' || return
      ;;
    ha-*)
      require_trace '--atomic' || return
      if [[ "$scenario" == ha-ok ]]
      then
        require_trace 'virsh blockcommit' || return
        require_trace 'disk pivot --inactive' || return
        require_trace 'sudo -n rm --' || return
      else
        reject_trace 'sudo -n rm --' || return
        grep -Fq 'Preserve' "$TEST_OUTPUT" || return 1
        case "$scenario" in
          ha-snapshot-fails|ha-snapshot-no-switch)
            reject_trace 'rsync ' || return
            reject_trace 'virsh blockcommit' || return
            ;;
          ha-copy-fails|ha-nvram-fails|ha-term)
            reject_trace 'virsh blockcommit' || return
            ;;
        esac
      fi
      ;;
  esac
}

test_main() {
  if [[ "${1:-}" == --help || "${1:-}" == -h ]]
  then
    usage
    return 0
  fi
  if [[ "${1:-}" == --case ]]
  then
    run_scenario "$2" "$3"
    return
  fi
  [[ $# -eq 0 ]] || return 2
  local test_dir script case_dir scenario status failures=0 count=0
  test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  script="${test_dir}/../migrate-fnuc-to-lrz.sh"
  export TEST_SELF="${test_dir}/$(basename -- "${BASH_SOURCE[0]}")"
  case_dir=$(mktemp -d -t migration-tests.XXXXXXXX)
  # Cleanup is confined to the exact directory created by this test run.
  trap 'rm -rf -- "${case_dir}"' EXIT
  local scenarios=(
    srv-ok srv-inactive srv-copy-fails srv-stop-fails srv-start-fails srv-term srv-dry
    ha-ok ha-off ha-dry-running ha-dry-off
    ha-dest-running ha-dest-paused ha-dest-query-fails
    ha-source-paused ha-source-unknown ha-source-query-fails
    ha-live-overlay ha-inactive-overlay ha-disk-query-fails
    ha-snapshot-fails ha-snapshot-no-switch ha-copy-fails ha-nvram-fails
    ha-commit-fails ha-pivot-live-overlay ha-pivot-inactive-overlay ha-term
  )
  for scenario in "${scenarios[@]}"
  do
    export TEST_TRACE="${case_dir}/${scenario}.trace"
    export TEST_OUTPUT="${case_dir}/${scenario}.output"
    : > "$TEST_TRACE"
    status=0
    bash "$TEST_SELF" --case "$scenario" "$script" > "$TEST_OUTPUT" 2>&1 || status=$?
    count=$((count + 1))
    if check_scenario "$scenario" "$status"
    then
      printf 'PASS %s\n' "$scenario"
    else
      printf 'FAIL %s (exit %s)\n' "$scenario" "$status" >&2
      cat "$TEST_OUTPUT" "$TEST_TRACE" >&2
      failures=$((failures + 1))
    fi
  done
  printf '%s scenarios, %s failures\n' "$count" "$failures"
  # Run cleanup while the local directory variable remains in scope.
  rm -rf -- "$case_dir"
  trap - EXIT
  [[ "$failures" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  test_main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
