#!/usr/bin/env bash

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") [--json] COMMAND [SERVICE]

Commands:
  list                 List declared services and status (plus the app-managed adb-shell)
  start SERVICE        Start a service
  stop SERVICE         Stop a service
  restart SERVICE      Restart a service
  show SERVICE         Show a service: state, PID, uptime, ports and settings
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

  # Per-service settings from the TermuxPP app's services page. Each key is
  # optional and replaces the configured value: enabled (start on boot),
  # wifiRestricted (stop outside the allowed networks, restart when back)
  # and allowedSsids.
  local settings=${NIXPP_SVC_SETTINGS:-$runtime/settings.json}

  # Prints the JSON value of KEY in SERVICE's settings, nothing when unset.
  setting() {
    [[ -r $settings ]] || return 0
    jq -c --arg name "$1" --arg key "$2" \
      '(.[$name] // {}) | if type == "object" and has($key) then .[$key] else empty end' \
      "$settings" 2>/dev/null || true
  }

  service_enabled() {
    local value
    value=$(setting "$1" enabled)
    [[ -n $value ]] || value=$(jq -c --arg name "$1" '.[$name].enabled' "$manifest")
    [[ $value == true ]]
  }

  # TEXT with the extended regex metacharacters escaped.
  regex_quote() {
    local text=$1 quoted='' character index
    for ((index = 0; index < ${#text}; index++))
    do
      character=${text:index:1}
      case $character in
        '['|']'|\\|'.'|'*'|'^'|'$'|'('|')'|'+'|'?'|'{'|'}'|'|') quoted+="\\$character" ;;
        *) quoted+=$character ;;
      esac
    done
    printf '%s' "$quoted"
  }

  # The configured allow-list file of SERVICE (a secret with one Wi-Fi
  # name per line), empty when it lists the names inline.
  ssids_file() {
    jq -r --arg name "$1" '.[$name].allowedSsidsFile // empty' "$manifest"
  }

  # Prints the configured allow-list of SERVICE, one name per line. An
  # unreadable file allows no network, so a missing secret cannot lift the
  # restriction.
  configured_ssids() {
    local file
    file=$(ssids_file "$1")
    if [[ -z $file ]]
    then
      jq -r --arg name "$1" '.[$name].allowedSsids // [] | .[]' "$manifest"
    elif [[ -r $file ]]
    then
      tr -d '\r' <"$file" | grep -v '^[[:space:]]*$' || true
    else
      printf 'svc: %s: cannot read the Wi-Fi allow-list %s; allowing no network\n' "$1" "$file" >&2
    fi
  }

  # Prints the effective allow-list of SERVICE, one name per line.
  allowed_ssids() {
    local value
    value=$(setting "$1" allowedSsids)
    if [[ -n $value ]]
    then
      jq -r '.[]? | strings' <<<"$value"
    else
      configured_ssids "$1"
    fi
  }

  # The restriction is on when the app says so, otherwise when the
  # configuration lists networks or names a file. On with an empty list
  # allows no network.
  network_restricted() {
    local value
    value=$(setting "$1" wifiRestricted)
    if [[ -n $value ]]
    then
      [[ $value == true ]]
    else
      jq -e --arg name "$1" \
        '((.[$name].allowedSsids // []) | length > 0) or (.[$name].allowedSsidsFile != null)' \
        "$manifest" >/dev/null
    fi
  }

  # Succeeds when SERVICE has no allow-list or the current Wi-Fi is on it.
  network_allows() {
    local name=$1
    local ssid
    local allowed
    if ! network_restricted "$name"
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
    # runsv starts a service only on `sv up` from svc, never by itself, so
    # start on boot and stops by hand or for the network hold across runs.
    : >"$destination/down" || return 1
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
    active_generation >/dev/null || return 1
    copy_service "$name" || return 1
    wait_for_supervisor "$name" || return 1
    if [[ $(sv status "$directory") == *"want exit"* ]]
    then
      die "the supervisor for $name is retiring"
      return 1
    fi
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
    local retired=
    exec 9>"$lock_file"
    flock 9 || return 1
    for directory in "$services_dir"/*
    do
      [[ -d $directory ]] || continue
      while supervisor_present "$directory" && ! sv -w 15 down "$directory" >/dev/null
      do
        sleep 1
      done
    done
    kill -TERM "$runsvdir_pid" 2>/dev/null || true
    wait "$runsvdir_pid" 2>/dev/null || true
    for directory in "$services_dir"/*
    do
      [[ -d $directory ]] || continue
      sv -w 0 exit "$directory" >/dev/null 2>&1 || true
    done
    for directory in "$services_dir"/*
    do
      if [[ -d $directory ]] && supervisor_present "$directory"
      then
        # A session can hold the old log pipe open after its listener exits.
        # Keep its control FIFOs and log directory away from the new tree.
        retired=$(mktemp -d "$runtime/retired.XXXXXXXX") || return 1
        mv -- "$logs_dir" "$retired/logs" || return 1
        mv -- "$services_dir" "$retired/services" || return 1
        mkdir -p "$services_dir" "$logs_dir" || return 1
        break
      fi
    done
    exec 9>&-
    exec 7>&-
    if [[ -n $retired ]]
    then
      for directory in "$retired/services"/*
      do
        [[ -d $directory ]] || continue
        while supervisor_present "$directory"
        do
          sleep 1
        done
      done
      rm -rf -- "${retired:?}/services"
    fi
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
    # The nixpp launcher holds the generation lease on fd 8.
    exec 7>"$runtime/supervisor.lock"
    if ! flock -n 7
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
      if service_enabled "$service" && [[ ! -e "$desired_dir/$service.stopped" ]]
      then
        copy_service "$service" || return 1
      fi
    done < <(jq -r 'keys[]' "$manifest")
    # Directories from older runs lack the down file; without it runsvdir
    # would start every service, ignoring start on boot.
    for directory in "$services_dir"/*
    do
      [[ -d $directory ]] && : >"$directory/down"
    done
    exec 9>&-

    runsvdir -P "$services_dir" 7>&- &
    runsvdir_pid=$!
    while IFS= read -r service
    do
      if service_enabled "$service" && [[ ! -e "$desired_dir/$service.stopped" ]]
      then
        if ! network_allows "$service"
        then
          # Starts once the network allows it.
          : >"$desired_dir/$service.network-down"
          continue
        fi
        start_service "$service" || {
          shutdown_supervisors "$runsvdir_pid"
          return 1
        }
      fi
    done < <(jq -r 'keys[]' "$manifest")

    local all_services=()
    mapfile -t all_services < <(jq -r 'keys[]' "$manifest")

    # Wait for changes instead of polling: the inputs are the settings, the
    # desired-state markers, the Wi-Fi state, the selected generation and the
    # APK marker. Wake every 10 seconds anyway (daemon and runsvdir alive?)
    # and evaluate at least once a minute (stale Wi-Fi state stops services).
    local selector_dir=${NIXPP_SVC_SELECTOR:-/run/nixpp-runtime/current-system}
    selector_dir=${selector_dir%/*}
    local network_file=${NIXPP_SVC_NETWORK:-$selector_dir/network.json}
    local inputs=("$settings" "$desired_dir" "$network_file" "$selector_dir/current-system" "$selector_dir/apk-library")
    local ssids_files=() service file
    for service in "${all_services[@]}"
    do
      file=$(ssids_file "$service")
      [[ -n $file ]] && ssids_files+=("$file")
    done
    inputs+=("${ssids_files[@]}")
    # Watch the inputs' directories, but report only the inputs themselves:
    # this loop's own lock and stamp files must not wake it.
    local watch_dirs=() include='' directory
    for file in "${inputs[@]}"
    do
      if [[ $file == "$desired_dir" ]]
      then
        directory=$desired_dir
        include+="|$(regex_quote "$desired_dir")/.*"
      else
        directory=${file%/*}
        include+="|$(regex_quote "$file")"
      fi
      [[ " ${watch_dirs[*]} " == *" $directory "* ]] || watch_dirs+=("$directory")
    done
    include="^(${include#|})\$"
    local stamp=$runtime/.supervise-stamp evaluate=1 idle=0 input
    # Once inotifywait fails (missing, or crashing: it segfaults in the
    # Android 17 guest), poll the inputs' mtimes instead, as rarely as the
    # inotify timeout would wake.
    local inotify=1 wait_rc poll=${NIXPP_SVC_POLL_SECONDS:-10}

    while kill -0 "$runsvdir_pid" 2>/dev/null
    do
      # The native daemon that started this tree died: retire, so its
      # successor can take over instead of finding an unowned tree.
      if [[ -n ${NIXPP_SVC_OWNER_PID:-} ]] && ! kill -0 "$NIXPP_SVC_OWNER_PID" 2>/dev/null
      then
        break
      fi
      # Follow Wi-Fi changes; the settings may change at any time (the app's
      # services page). Stop a running restricted service outside its
      # networks and mark it .network-down; restart only those once allowed.
      # Services that are off or were stopped by hand (.stopped) stay off.
      if ((evaluate && ${#all_services[@]}))
      then
        # Inputs newer than this stamp changed after this pass began.
        : >"$stamp"
        exec 9>"$lock_file"
        flock 9
        for service in "${all_services[@]}"
        do
          if [[ -e "$desired_dir/$service.stopped" ]]
          then
            rm -f -- "${desired_dir:?}/${service:?}.network-down"
            continue
          fi
          if network_allows "$service"
          then
            if [[ -e "$desired_dir/$service.network-down" ]]
            then
              [[ $(service_status "$service") == running ]] || start_service "$service" || true
              rm -f -- "${desired_dir:?}/${service:?}.network-down"
            fi
          elif [[ $(service_status "$service") != down ]]
          then
            # Mark first: readers never see it stopped but unmarked.
            : >"$desired_dir/$service.network-down"
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
      # An input changed while this pass ran: run again before waiting.
      evaluate=0
      for input in "${inputs[@]}"
      do
        [[ $input -nt $stamp ]] && evaluate=1
      done
      ((evaluate)) && continue
      wait_rc=2
      if ((inotify))
      then
        inotifywait -qq -t 10 -e close_write,moved_to,moved_from,create,delete,attrib \
          --include "$include" "${watch_dirs[@]}" 2>/dev/null && wait_rc=0 || wait_rc=$?
      else
        sleep "$poll"
      fi
      case $wait_rc in
        0)
          evaluate=1 idle=0
          ;;
        2)
          # Timed out (or polled): catch a change that landed before the wait
          # began (builtin tests, no process), and the minute-long staleness.
          idle=$((idle + 1))
          for input in "${inputs[@]}"
          do
            [[ $input -nt $stamp ]] && evaluate=1
          done
          ((idle % 6 == 0)) && evaluate=1
          ;;
        *)
          # No usable inotifywait: poll from now on. Evaluate once, since a
          # change may have landed while it failed.
          inotify=0 evaluate=1
          ;;
      esac
    done
    shutdown_supervisors "$runsvdir_pid"
    return 75
  }

  # Prints "pid seconds" of a running service, nothing otherwise.
  service_process() {
    local status
    supervisor_present "$services_dir/$1" || return 0
    status=$(sv status "$services_dir/$1" 2>/dev/null) || return 0
    if [[ $status =~ ^run:\ [^:]+:\ \(pid\ ([0-9]+)\)\ ([0-9]+)s ]]
    then
      printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
  }

  # Prints "protocol address:port" for each listening socket of PID and its
  # children. Android may withhold /proc/net; then nothing is printed.
  listening_ports() {
    local pid=$1 process fd target inode
    local -A inodes=()
    for process in "$pid" $(pgrep -P "$pid" 2>/dev/null)
    do
      for fd in /proc/"$process"/fd/*
      do
        target=$(readlink "$fd" 2>/dev/null) || continue
        [[ $target =~ ^socket:\[([0-9]+)\]$ ]] && inodes[${BASH_REMATCH[1]}]=1
      done
    done
    ((${#inodes[@]})) || return 0
    local protocol table
    local -a line
    for protocol in tcp tcp6 udp udp6
    do
      table=/proc/net/$protocol
      [[ -r $table ]] || continue
      while read -r -a line
      do
        inode=${line[9]:-}
        [[ -n $inode && -n ${inodes[$inode]:-} ]] || continue
        # TCP sockets count only while listening (state 0A).
        [[ $protocol == udp* || ${line[3]} == 0A ]] || continue
        local address=${line[1]%:*} port=$((16#${line[1]#*:}))
        if [[ $address =~ ^0+$ ]]
        then
          address='*'
        elif ((${#address} == 8))
        then
          address=$((16#${address:6:2})).$((16#${address:4:2})).$((16#${address:2:2})).$((16#${address:0:2}))
        fi
        printf '%s %s:%s\n' "$protocol" "$address" "$port"
      done < <(tail -n +2 "$table")
    done | sort -u
  }

  # One service as JSON: state, process and the effective settings, with the
  # app's settings and the configured values for comparison.
  service_json() {
    local name=$1 status pid='' uptime='' network=null ssids ports='[]' command=''
    status=$(service_status "$name")
    read -r pid uptime < <(service_process "$name") || true
    if [[ -n $pid ]]
    then
      ports=$(listening_ports "$pid" | jq -R . | jq -sc .)
      command=$(tr '\0' ' ' 2>/dev/null <"/proc/$pid/cmdline" || true)
    fi
    if network_restricted "$name"
    then
      network='"blocked"'
      network_allows "$name" && network='"allowed"'
    fi
    ssids=$(allowed_ssids "$name" | jq -R . | jq -sc .)
    local enabled=false restricted=false waiting=false stopped=false own='{}'
    service_enabled "$name" && enabled=true
    network_restricted "$name" && restricted=true
    [[ -e "$desired_dir/$name.network-down" ]] && waiting=true
    [[ -e "$desired_dir/$name.stopped" ]] && stopped=true
    if [[ -r $settings ]]
    then
      own=$(jq -c --arg name "$name" '.[$name] // {}' "$settings" 2>/dev/null) || own='{}'
    fi
    jq -cn --arg name "$name" --arg status "$status" \
      --arg pid "$pid" --arg uptime "$uptime" --arg command "${command% }" \
      --argjson ports "$ports" --argjson enabled "$enabled" --argjson restricted "$restricted" \
      --argjson ssids "$ssids" --argjson network "$network" --argjson settings "$own" \
      --argjson configured "$(jq -c --arg name "$name" --argjson ssids "$(configured_ssids "$name" 2>/dev/null | jq -R . | jq -sc .)" \
        '.[$name] | {enabled, allowedSsids: $ssids}' "$manifest")" \
      --argjson waiting "$waiting" --argjson stopped "$stopped" \
      '{name: $name, status: $status, enabled: $enabled, wifiRestricted: $restricted,
        allowedSsids: $ssids, waitingForNetwork: $waiting, stoppedByUser: $stopped,
        settings: $settings, configured: $configured,
        ssidsOverridden: ($settings | has("allowedSsids"))}
       + (if $network == null then {} else {network: $network} end)
       + (if $pid == "" then {} else {pid: ($pid | tonumber), uptimeSeconds: ($uptime | tonumber),
          command: $command, listening: $ports} end)'
  }

  show_service() {
    local json
    json=$(service_json "$1") || return 1
    if ((json_output))
    then
      printf '%s\n' "$json"
      return
    fi
    jq -r --arg log "$logs_dir/$1/current" '
      def origin(key): if .settings | has(key) then " (set in the app)" else " (configuration)" end;
      def duration: if . >= 86400 then "\(. / 86400 | floor)d \(. % 86400 / 3600 | floor)h"
        elif . >= 3600 then "\(. / 3600 | floor)h \(. % 3600 / 60 | floor)m"
        elif . >= 60 then "\(. / 60 | floor)m \(. % 60)s" else "\(.)s" end;
      "\(.name)",
      "  status:        \(.status)"
        + (if .pid then " (pid \(.pid), up \(.uptimeSeconds | duration))" else "" end)
        + (if .stoppedByUser then ", stopped by hand"
           elif .waitingForNetwork then ", waiting for an allowed Wi-Fi network" else "" end),
      "  start on boot: \(if .enabled then "yes" else "no" end)" + origin("enabled"),
      "  wifi:          " + (if .wifiRestricted
          then "only on \(if (.allowedSsids | length) == 0 then "(no network)" else .allowedSsids | join(", ") end)"
            + (if .network == "allowed" then ", allowed here"
               elif .network == "blocked" then ", not allowed here" else "" end)
          else "any network" end) + origin("wifiRestricted"),
      (if (.listening // []) | length > 0 then "  listening:     \(.listening | join(", "))" else empty end),
      (if .command then "  command:       \(.command)" else empty end),
      "  log:           \($log)"' <<<"$json"
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
          result=$(jq -cn --argjson items "$result" --argjson item "$(service_json "$service_name")" '$items + [$item]')
        done < <(jq -r 'keys[]' "$manifest")
        result=$(jq -cn --argjson items "$result" --arg status "$(adb_shell_status)" \
          '$items + [{name:"adb-shell",status:$status,enabled:true,external:true}]')
        printf '%s\n' "$result"
      else
        while IFS= read -r service_name
        do
          local note=
          if [[ -e "$desired_dir/$service_name.network-down" ]]
          then
            note=' (waiting for an allowed Wi-Fi network)'
          elif network_restricted "$service_name" && ! network_allows "$service_name"
          then
            note=' (not on an allowed Wi-Fi network)'
          fi
          printf '%-24s %s%s\n' "$service_name" "$(service_status "$service_name")" "$note"
        done < <(jq -r 'keys[]' "$manifest")
        printf '%-24s %s\n' adb-shell "$(adb_shell_status) (managed by the TermuxPP app)"
      fi
      ;;
    start|stop|restart|logs|show)
      if [[ $# -ne 1 ]]
      then
        usage >&2
        return 2
      fi
      service_name=$1
      service_exists "$service_name" || return 1
      if [[ $command == show ]]
      then
        show_service "$service_name"
        return
      fi
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
      active_generation >/dev/null || return 1
      local supervised_generation
      if ! IFS= read -r supervised_generation < "$runtime/system-generation" ||
        [[ $supervised_generation != "$generation" ]]
      then
        die "the service supervisor is changing generations"
        return 1
      fi
      case $command in
        start)
          rm -f -- "$desired_dir/$service_name.stopped"
          start_service "$service_name"
          ;;
        stop)
          stop_service "$service_name" || return 1
          : >"$desired_dir/$service_name.stopped"
          rm -f -- "${desired_dir:?}/${service_name:?}.network-down"
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
