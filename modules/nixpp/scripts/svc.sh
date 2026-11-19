#!/usr/bin/env bash

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") [--json] COMMAND [SERVICE]

Commands:
  list                 List declared services and status (plus the app-managed adb-shell)
  start SERVICE        Start a service
  stop SERVICE         Stop a service
  restart SERVICE      Restart a service
  logs SERVICE         Show recent service output
  supervise            Internal foreground runit supervisor
EOF_USAGE
}

die() {
  printf 'svc: %s\n' "$*" >&2
  return 1
}

service_name_valid() {
  [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.@-]*$ ]]
}

supervisor_present() {
  sv status "$1" >/dev/null 2>&1
}

selected_generation() {
  local selector=${NIXPP_SVC_SELECTOR:-/run/nixpp-runtime/current-system}
  local selected_name
  local generation_file
  local generation
  if ! IFS= read -r selected_name < "$selector" || ! service_name_valid "$selected_name"
  then
    die "no selected guest system"
    return 1
  fi
  generation_file=${selector%/*}/system-candidates/$selected_name/generation
  if ! IFS= read -r generation < "$generation_file" ||
    [[ ! $generation =~ ^/nix/store/[a-z0-9]{32}-[a-zA-Z0-9+._-]+$ ]]
  then
    die "selected guest system is unavailable"
    return 1
  fi
  printf '%s\n' "$generation"
}

active_generation() {
  local active_system=${NIXPP_SVC_CURRENT_SYSTEM:-/run/current-system}
  local generation
  generation=$(selected_generation) || return 1
  if [[ ! $active_system -ef $generation ]]
  then
    die "this session is not running the selected guest system"
    return 1
  fi
  printf '%s\n' "$generation"
}

service_status() {
  local directory=$runtime/services/$1
  local status
  if ! supervisor_present "$directory"
  then
    printf 'down'
    return 0
  fi
  status=$(sv status "$directory" 2>&1) || true
  case $status in
    run:*) printf 'running' ;;
    down:*) printf 'down' ;;
    *) printf 'unknown' ;;
  esac
}

# The TermuxPP app publishes the connected Wi-Fi name here and refreshes the
# file at least every minute. A missing, unreadable or stale file, no Wi-Fi or
# a name Android withholds all mean "unknown": restricted services stay down.
current_ssid() {
  local selector=${NIXPP_SVC_SELECTOR:-/run/nixpp-runtime/current-system}
  local network=${NIXPP_SVC_NETWORK:-${selector%/*}/network.json}
  local max_age=${NIXPP_SVC_NETWORK_MAX_AGE:-300}
  local modified
  modified=$(stat -c %Y -- "$network" 2>/dev/null) || return 1
  (($(date +%s) - modified <= max_age)) || return 1
  jq -er '.ssid | strings | select(length > 0)' "$network" 2>/dev/null
}

# The ADB shell listener belongs to the Android app, not to the guest
# supervisor, so it is listed read-only and probed on its loopback port.
adb_shell_status() {
  if timeout 1 bash -c ": </dev/tcp/127.0.0.1/${NIXPP_SVC_ADB_PORT:-5522}" 2>/dev/null
  then
    printf 'running'
  else
    printf 'down'
  fi
}

main() {
  local json_output=0
  local command
  local service_name
  local manifest=${NIXPP_SVC_MANIFEST:-/etc/nixpp/services.json}
  local runtime=${NIXPP_SVC_RUNTIME_DIR:-/run/nixpp-runtime/service-state}
  local services_dir=$runtime/services
  local desired_dir=$runtime/desired-state
  local logs_dir=$runtime/logs
  local generation
  local lock_file=$runtime/control.lock

  if [[ ${1:-} == --json ]]
  then
    json_output=1
    shift
  fi

  if [[ $# -lt 1 ]]
  then
    usage >&2
    return 2
  fi

  command=$1
  shift

  if [[ $command == --help || $command == -h ]]
  then
    usage
    return 0
  fi

  if [[ ! -r $manifest ]]
  then
    die "service manifest is unavailable"
    return 1
  fi

  generation=$(active_generation) || return 1
  mkdir -p "$services_dir" "$desired_dir" "$logs_dir" || return 1

  allowed_ssids() {
    jq -r --arg name "$1" '.[$name].allowedSsids // [] | .[]' "$manifest"
  }

  # Succeeds when SERVICE has no allow-list or the current Wi-Fi is on it.
  network_allows() {
    local name=$1
    local ssid
    local allowed
    if ! jq -e --arg name "$name" '(.[$name].allowedSsids // []) | length > 0' "$manifest" >/dev/null
    then
      return 0
    fi
    ssid=$(current_ssid) || return 1
    while IFS= read -r allowed
    do
      [[ $allowed == "$ssid" ]] && return 0
    done < <(allowed_ssids "$name")
    return 1
  }

  network_restricted() {
    jq -e --arg name "$1" '(.[$name].allowedSsids // []) | length > 0' "$manifest" >/dev/null
  }

  service_exists() {
    service_name=$1
    service_name_valid "$service_name" || {
      die "invalid service name"
      return 1
    }
    if [[ $service_name == adb-shell ]]
    then
      die "adb-shell is managed by the TermuxPP app (Settings > Debugging)"
      return 1
    fi
    jq -e --arg name "$service_name" '.[$name] != null' "$manifest" >/dev/null || {
      die "unknown service: $service_name"
      return 1
    }
  }

  copy_service() {
    local name=$1
    local source
    local destination=$services_dir/$name
    source=$(jq -er --arg name "$name" '.[$name].directory' "$manifest") || return 1
    if [[ ! -x $destination/run || ! -x $destination/log/run ]]
    then
      local temporary=$services_dir/.$name.$$
      rm -rf -- "$temporary" || return 1
      cp -R -- "$source" "$temporary" || return 1
      chmod -R u+rwX -- "$temporary" || return 1
      mkdir -p "$logs_dir/$name" || return 1
      ln -s "$logs_dir/$name" "$temporary/log/main" || return 1
      mv -T -- "$temporary" "$destination" || return 1
    fi
  }

  wait_for_supervisor() {
    local directory=$services_dir/$1
    local attempt
    for ((attempt = 0; attempt < 100; attempt++))
    do
      supervisor_present "$directory" && return 0
      sleep 0.1
    done
    die "supervisor is unavailable for $1"
  }

  start_service() {
    local name=$1
    local directory=$services_dir/$name
    copy_service "$name" || return 1
    wait_for_supervisor "$name" || return 1
    sv -w 10 up "$directory" >/dev/null
  }

  stop_service() {
    local directory=$services_dir/$1
    if supervisor_present "$directory"
    then
      sv -w 10 down "$directory" >/dev/null
    fi
  }

  shutdown_supervisors() {
    local runsvdir_pid=$1
    local directory
    local attempt
    for directory in "$services_dir"/*
    do
      [[ -d $directory ]] || continue
      sv -w 15 down "$directory" >/dev/null 2>&1 || true
    done
    kill -TERM "$runsvdir_pid" 2>/dev/null || true
    wait "$runsvdir_pid" 2>/dev/null || true
    for directory in "$services_dir"/*
    do
      [[ -d $directory ]] || continue
      sv exit "$directory" >/dev/null 2>&1 || true
      for ((attempt = 0; attempt < 50; attempt++))
      do
        supervisor_present "$directory" || break
        sleep 0.1
      done
    done
  }

  apk_library() {
    local selector=${NIXPP_SVC_SELECTOR:-/run/nixpp-runtime/current-system}
    local marker=${selector%/*}/apk-library
    local library
    if [[ -r $marker ]] && IFS= read -r library < "$marker"
    then
      printf '%s\n' "$library"
    fi
  }

  supervise_services() {
    local selected
    local old_generation=
    local directory
    local service
    local runsvdir_pid
    local loaded_apk
    loaded_apk=${NIXPP_SVC_APK_LIBRARY-$(apk_library)}
    selected=$(active_generation) || return 1
    exec 8>"$runtime/supervisor.lock"
    if ! flock -n 8
    then
      die "a guest service supervisor is already running"
      return 76
    fi
    exec 9>"$lock_file"
    flock 9
    # The TermuxPP Tasker plug-in lists the services from this copy.
    if cp -- "$manifest" "$runtime/.manifest.json.$$" 2>/dev/null
    then
      mv -f -- "$runtime/.manifest.json.$$" "$runtime/manifest.json" || rm -f -- "$runtime/.manifest.json.$$"
    fi
    if [[ -r $runtime/system-generation ]]
    then
      IFS= read -r old_generation < "$runtime/system-generation"
    fi
    if [[ $old_generation != "$selected" ]]
    then
      for directory in "$services_dir"/*
      do
        [[ -d $directory ]] || continue
        sv -w 10 down "$directory" >/dev/null 2>&1 || true
        sv exit "$directory" >/dev/null 2>&1 || true
      done
      for directory in "$services_dir"/*
      do
        [[ -d $directory ]] || continue
        local attempt
        for ((attempt = 0; attempt < 50; attempt++))
        do
          supervisor_present "$directory" || break
          sleep 0.1
        done
        if supervisor_present "$directory"
        then
          return 76
        fi
      done
      rm -rf -- "$services_dir" || return 1
      mkdir -p "$services_dir" "$desired_dir" || return 1
      printf '%s\n' "$selected" >"$runtime/system-generation"
    fi
    while IFS= read -r service
    do
      if [[ $(jq -r --arg name "$service" '.[$name].enabled' "$manifest") == true &&
        ! -e "$desired_dir/$service.stopped" ]]
      then
        copy_service "$service" || return 1
      fi
    done < <(jq -r 'keys[]' "$manifest")
    exec 9>&-

    runsvdir -P "$services_dir" 8>&- &
    runsvdir_pid=$!
    while IFS= read -r service
    do
      if [[ $(jq -r --arg name "$service" '.[$name].enabled' "$manifest") == true &&
        ! -e "$desired_dir/$service.stopped" ]] && network_allows "$service"
      then
        start_service "$service" || {
          shutdown_supervisors "$runsvdir_pid"
          return 1
        }
      fi
    done < <(jq -r 'keys[]' "$manifest")

    local restricted=()
    while IFS= read -r service
    do
      if [[ $(jq -r --arg name "$service" '.[$name].enabled' "$manifest") == true ]] &&
        network_restricted "$service"
      then
        restricted+=("$service")
      fi
    done < <(jq -r 'keys[]' "$manifest")

    while kill -0 "$runsvdir_pid" 2>/dev/null
    do
      # Follow Wi-Fi changes for restricted services. A manual `svc stop`
      # (the .stopped marker) always wins; network stops leave no marker.
      if ((${#restricted[@]}))
      then
        exec 9>"$lock_file"
        flock 9
        for service in "${restricted[@]}"
        do
          [[ -e "$desired_dir/$service.stopped" ]] && continue
          if network_allows "$service"
          then
            [[ $(service_status "$service") == running ]] || start_service "$service" || true
          elif [[ $(service_status "$service") != down ]]
          then
            stop_service "$service" || true
          fi
        done
        exec 9>&-
      fi
      selected=$(selected_generation) || selected=
      if [[ $(apk_library) != "$loaded_apk" || $selected != "$generation" ||
        ! ${NIXPP_SVC_CURRENT_SYSTEM:-/run/current-system} -ef $generation ]]
      then
        break
      fi
      sleep 1
    done
    shutdown_supervisors "$runsvdir_pid"
    return 75
  }

  case $command in
    list)
      if [[ $# -ne 0 ]]
      then
        usage >&2
        return 2
      fi
      if ((json_output))
      then
        local result='[]'
        while IFS= read -r service_name
        do
          local enabled status network=null
          enabled=$(jq -r --arg name "$service_name" '.[$name].enabled' "$manifest")
          status=$(service_status "$service_name")
          if network_restricted "$service_name"
          then
            network='"blocked"'
            network_allows "$service_name" && network='"allowed"'
          fi
          result=$(jq -cn --argjson items "$result" --arg name "$service_name" --arg status "$status" --argjson enabled "$enabled" \
            --argjson network "$network" \
            '$items + [{name:$name,status:$status,enabled:$enabled} + (if $network == null then {} else {network:$network} end)]')
        done < <(jq -r 'keys[]' "$manifest")
        result=$(jq -cn --argjson items "$result" --arg status "$(adb_shell_status)" \
          '$items + [{name:"adb-shell",status:$status,enabled:true,external:true}]')
        printf '%s\n' "$result"
      else
        while IFS= read -r service_name
        do
          local note=
          if network_restricted "$service_name" && ! network_allows "$service_name"
          then
            note=' (waiting for an allowed Wi-Fi network)'
          fi
          printf '%-24s %s%s\n' "$service_name" "$(service_status "$service_name")" "$note"
        done < <(jq -r 'keys[]' "$manifest")
        printf '%-24s %s\n' adb-shell "$(adb_shell_status) (managed by the TermuxPP app)"
      fi
      ;;
    start|stop|restart|logs)
      if [[ $# -ne 1 ]]
      then
        usage >&2
        return 2
      fi
      service_name=$1
      service_exists "$service_name" || return 1
      if [[ $command == logs ]]
      then
        local log_file=$logs_dir/$service_name/current
        if [[ ! -r $log_file ]]
        then
          die "no logs are available for $service_name"
          return 1
        fi
        tail -c 65536 "$log_file" | tail -n 200
        return
      fi
      if [[ $command == start || $command == restart ]] && ! network_allows "$service_name"
      then
        die "$service_name may only run on its allowed Wi-Fi networks (current: $(current_ssid || printf 'unknown'))"
        return 1
      fi
      exec 9>"$lock_file"
      flock 9
      case $command in
        start)
          rm -f -- "$desired_dir/$service_name.stopped"
          start_service "$service_name"
          ;;
        stop)
          stop_service "$service_name" || return 1
          : >"$desired_dir/$service_name.stopped"
          ;;
        restart)
          stop_service "$service_name" || return 1
          rm -f -- "$desired_dir/$service_name.stopped"
          start_service "$service_name"
          ;;
      esac
      ;;
    supervise)
      if [[ $# -ne 0 || $json_output -eq 1 ]]
      then
        usage >&2
        return 2
      fi
      supervise_services
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
