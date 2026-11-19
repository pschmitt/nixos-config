#!/usr/bin/env bash

PACKAGE=${TERMUXPP_PACKAGE:-dev.pschmitt.termux}
RUNTIME_DIR=${NIXPP_RUNTIME:-/run/nixpp-runtime}
STATE_FILE=$RUNTIME_DIR/permissions.json
PERMISSION_ACTIVITY=$PACKAGE/$PACKAGE.api.activities.TermuxApiPermissionActivity
PERMISSION_EXTRA=$PACKAGE.api.permission_extra

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") [status | grant [NAME...]] [--no-shizuku]

Show and grant the Android permissions TermuxPP requests: every runtime
permission (location, notifications, camera, ...) and the special access
Android grants on separate pages (overlay, storage, install, alarms,
usage, settings, battery) plus Android's child process limit, which kills
the nixpp controller.

Commands:
  status        Show what is granted and what is missing (default)
  grant [NAME]  Grant everything missing, or only NAME (for example
                ACCESS_BACKGROUND_LOCATION, POST_NOTIFICATIONS, overlay,
                storage, install, alarms, usage, settings, battery,
                processes)

grant first asks Shizuku for permission (Shizuku shows its dialog). Once
TermuxPP may use Shizuku, rish grants the rest without any confirmation.
Without Shizuku, or with --no-shizuku, Android asks: grant opens the dialogs
and then each special access page in turn, and status reads what the
TermuxPP app reports.
EOF_USAGE
}

die() {
  printf '%s: %s\n' "$(basename "$0")" "$*" >&2
  exit 1
}

# Special access: NAME PERMISSION APPOP SETTINGS_ACTION LABEL. APPOP "-"
# means the battery optimization allowlist instead of an app op.
SPECIAL_ACCESS=(
  "overlay android.permission.SYSTEM_ALERT_WINDOW SYSTEM_ALERT_WINDOW android.settings.action.MANAGE_OVERLAY_PERMISSION Display_over_other_apps"
  "storage android.permission.MANAGE_EXTERNAL_STORAGE MANAGE_EXTERNAL_STORAGE android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION All_files_access"
  "install android.permission.REQUEST_INSTALL_PACKAGES REQUEST_INSTALL_PACKAGES android.settings.MANAGE_UNKNOWN_APP_SOURCES Install_unknown_apps"
  "alarms android.permission.SCHEDULE_EXACT_ALARM SCHEDULE_EXACT_ALARM android.settings.REQUEST_SCHEDULE_EXACT_ALARM Alarms_and_reminders"
  "usage android.permission.PACKAGE_USAGE_STATS GET_USAGE_STATS android.settings.USAGE_ACCESS_SETTINGS Usage_access"
  "settings android.permission.WRITE_SETTINGS WRITE_SETTINGS android.settings.action.MANAGE_WRITE_SETTINGS Modify_system_settings"
  "battery android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS - android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS Unrestricted_battery"
)

# Android 12L+ kills app child processes (the nixpp controller, guest
# sessions) beyond a device-wide limit; this global setting turns that off.
PHANTOM_SETTING=settings_enable_monitor_phantom_procs

special_field() {
  local wanted=$1 field=$2 entry
  local -a parts
  for entry in "${SPECIAL_ACCESS[@]}"
  do
    read -r -a parts <<<"$entry"
    if [[ ${parts[0]} == "$wanted" ]]
    then
      printf '%s' "${parts[$field]}"
      return 0
    fi
  done
  return 1
}

# --- Shizuku -----------------------------------------------------------------

# rish loses output without a terminal, so it runs under script(1); each
# command ends with a marker and is retried until the marker comes back.
shizuku() {
  local marker=__termuxpp_rish_done__
  local command output attempt
  printf -v command 'rish -c %q' "$1; echo $marker \$?"
  for attempt in 1 2 3
  do
    output=$(timeout 60 script -qec "$command" /dev/null </dev/null 2>/dev/null | tr -d '\r') || true
    # The terminal echoes rish's NUL bytes as a literal "^@".
    output=${output//\^@/}
    if [[ $output == *"$marker "* ]]
    then
      output=${output#*Entering shell...$'\n'}
      printf '%s' "${output%"$marker "*}"
      [[ ${output##*"$marker "} == 0* ]]
      return
    fi
    sleep "$attempt"
  done
  return 1
}

shizuku_works() {
  command -v rish >/dev/null 2>&1 || return 1
  [[ $(shizuku 'id -u') == 2000* ]]
}

# Prints "NAME STATE KIND DETAIL" lines from the package state.
collect_shizuku() {
  local dump requested whitelist entry name permission appop action label mode state
  dump=$(shizuku "dumpsys package $PACKAGE") || die "cannot read the package state through Shizuku"
  requested=$(awk '
    /^ *requested permissions:/ { section = 1; next }
    section && /permissions:|^ *[A-Z][A-Za-z ]+:/ { section = 0 }
    section && $1 ~ /\./ { name = $1; sub(/:.*/, "", name); print name }
  ' <<<"$dump")
  # dumpsys lists runtime grants per Android user (a work profile adds one);
  # only the app's own user counts.
  awk -v user="${TERMUX__USER_ID:-0}" '
    /^ *User [0-9]+:/ { current = $2; sub(/:$/, "", current) }
    /^ *runtime permissions:/ { section = (current == "" || current == user); next }
    section && !/granted=/ { section = 0 }
    section && /granted=/ {
      name = $1; sub(/:$/, "", name)
      short = name; sub(/.*\./, "", short)
      print short, (($0 ~ /granted=true/) ? "granted" : "missing"), "runtime", name
    }
  ' <<<"$dump" | sort -u
  whitelist=$(shizuku 'dumpsys deviceidle whitelist') || whitelist=
  for entry in "${SPECIAL_ACCESS[@]}"
  do
    read -r name permission appop action label <<<"$entry"
    grep -qxF "$permission" <<<"$requested" || continue
    if [[ $appop == - ]]
    then
      state=missing
      grep -q ",$PACKAGE," <<<"$whitelist" && state=granted
    else
      mode=$(shizuku "appops get --user ${TERMUX__USER_ID:-0} $PACKAGE $appop" | head -n 1) || mode=
      state=missing
      [[ $mode == *": allow"* ]] && state=granted
    fi
    printf '%s %s special %s\n' "$name" "$state" "$label"
  done
  if [[ $(shizuku 'getprop ro.build.version.sdk') -ge 32 ]]
  then
    state=missing
    [[ $(shizuku "settings get global $PHANTOM_SETTING") == false* ]] && state=granted
    printf 'processes %s special Unrestricted_child_processes\n' "$state"
  fi
}

grant_shizuku() {
  local name=$1 kind=$2 detail=$3 appop
  if [[ $kind == runtime ]]
  then
    shizuku "pm grant --user ${TERMUX__USER_ID:-0} $PACKAGE $detail" >/dev/null
  elif [[ $name == processes ]]
  then
    shizuku "settings put global $PHANTOM_SETTING false" >/dev/null
  else
    appop=$(special_field "$name" 2)
    if [[ $appop == - ]]
    then
      shizuku "dumpsys deviceidle whitelist +$PACKAGE" >/dev/null
    else
      shizuku "appops set --user ${TERMUX__USER_ID:-0} $PACKAGE $appop allow" >/dev/null
    fi
  fi
}

# --- The app's own report, without Shizuku -----------------------------------

# --- Shizuku first -----------------------------------------------------------
# grant asks for Shizuku's permission before anything else: once TermuxPP may
# use Shizuku, rish (which runs as TermuxPP) grants the rest without prompts.

SHIZUKU_RECEIVER=$PACKAGE/com.termux.app.update.ShizukuCommandReceiver

# Run a Shizuku command in the app (request, open, refresh) and print the
# Shizuku state it then reports, empty for an app without that report.
app_shizuku() {
  local since
  since=$(date +%s)
  termux-am broadcast --user "${TERMUX__USER_ID:-0}" -n "$SHIZUKU_RECEIVER" \
    --es command "$1" >/dev/null 2>&1 || return 0
  local _
  for _ in $(seq 1 20)
  do
    if [[ $(jq -r '.updated // 0' "$STATE_FILE" 2>/dev/null) -ge $since ]]
    then
      jq -r '.shizuku // empty' "$STATE_FILE"
      return 0
    fi
    sleep 0.25
  done
}

shizuku_hint() {
  case $1 in
    UNAVAILABLE) printf 'Shizuku is not installed (https://shizuku.rikka.app); asking Android for each permission instead.\n' ;;
    NOT_RUNNING) printf 'Shizuku is installed but not running: start it in the Shizuku app. Asking Android instead.\n' ;;
    PERMISSION_DENIED) printf 'TermuxPP is denied in Shizuku (allow it under Authorized applications). Asking Android instead.\n' ;;
    UNSUPPORTED) printf 'This Shizuku is too old; update it. Asking Android instead.\n' ;;
    PERMISSION_NEEDED) printf 'Shizuku was not allowed in time. Asking Android instead.\n' ;;
  esac
}

# Succeeds when TermuxPP may use Shizuku, after asking for it when needed.
request_shizuku() {
  local state
  state=$(app_shizuku refresh)
  # An app without the Shizuku report: use rish when it already works.
  [[ -z $state ]] && return 0
  if [[ $state == PERMISSION_NEEDED ]]
  then
    printf 'Allow TermuxPP in the Shizuku dialog on the phone...\n'
    state=$(app_shizuku request)
    local _
    for _ in $(seq 1 60)
    do
      [[ $state == PERMISSION_NEEDED ]] || break
      sleep 1
      state=$(jq -r '.shizuku // empty' "$STATE_FILE")
    done
  fi
  [[ $state == READY ]] && return 0
  shizuku_hint "$state" >&2
  return 1
}

state_age() {
  local updated
  updated=$(jq -er '.updated' "$STATE_FILE" 2>/dev/null) || return 1
  printf '%s' $(($(date +%s) - updated))
}

collect_app() {
  local age
  age=$(state_age) ||
    die "TermuxPP has not reported its permissions yet: open the app (an updated build is needed) and try again"
  ((age <= 300)) || die "TermuxPP's permission report is ${age}s old: open the app and try again"
  jq -r '
    (.runtime // {} | to_entries[] |
      "\(.key | split(".") | last) \(if .value then "granted" else "missing" end) runtime \(.key)"),
    (.special // {} | to_entries[] |
      "\(.key) \(if .value then "granted" else "missing" end) special -")
  ' "$STATE_FILE" | while read -r name state kind detail
  do
    if [[ $name == processes ]]
    then
      detail=Unrestricted_child_processes
    elif [[ $kind == special ]]
    then
      detail=$(special_field "$name" 4)
    fi
    printf '%s %s %s %s\n' "$name" "$state" "$kind" "$detail"
  done
}

# The guest's termux-am starts activities with TermuxPP's identity, so it may
# open the app's own non-exported permission activity.
app_am() {
  local subcommand=$1
  shift
  termux-am "$subcommand" --user "${TERMUX__USER_ID:-0}" "$@" >/dev/null
}

wait_for_user() {
  if [[ -t 0 ]]
  then
    read -r -p "$1 Press Enter when done. " _
  else
    sleep 15
  fi
}

ask_runtime() {
  local list
  list=$(IFS=,; printf '%s' "$*")
  app_am start -n "$PERMISSION_ACTIVITY" --esal "$PERMISSION_EXTRA" "$list"
  wait_for_user "Answer Android's permission prompts on the phone."
}

ask_special() {
  local name=$1 action
  if [[ $name == processes ]]
  then
    app_am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS
    wait_for_user 'In Developer options, turn on "Disable child process restrictions".'
    return
  fi
  action=$(special_field "$name" 3)
  if [[ $name == usage ]]
  then
    app_am start -a "$action"
  else
    app_am start -a "$action" -d "package:$PACKAGE"
  fi
  wait_for_user "Allow \"$(special_field "$name" 4 | tr _ ' ')\" for TermuxPP."
}

# --- Commands ----------------------------------------------------------------

print_status() {
  local name state kind detail missing=0
  while read -r name state kind detail
  do
    [[ -n $name ]] || continue
    [[ $state == missing ]] && missing=$((missing + 1))
    if [[ $kind == runtime ]]
    then
      printf '  %-38s %s\n' "$name" "$state"
    else
      printf '  %-38s %s (%s)\n' "$name" "$state" "${detail//_/ }"
    fi
  done <<<"$1"
  printf '%d missing\n' "$missing"
  ((missing == 0))
}

# Prints the missing entries, filtered by NAMEs when given.
missing_entries() {
  local state=$1
  shift
  local name entry_state kind detail wanted
  while read -r name entry_state kind detail
  do
    [[ $entry_state == missing ]] || continue
    if (($#))
    then
      for wanted in "$@"
      do
        if [[ ${wanted^^} == "${name^^}" || ${wanted^^} == "${detail^^}" ]]
        then
          printf '%s %s %s %s\n' "$name" "$entry_state" "$kind" "$detail"
        fi
      done
    else
      printf '%s %s %s %s\n' "$name" "$entry_state" "$kind" "$detail"
    fi
  done <<<"$state"
}

main() {
  local command=status use_shizuku=1 names=() argument
  for argument in "$@"
  do
    case $argument in
      -h|--help)
        usage
        return 0
        ;;
      --no-shizuku) use_shizuku=0 ;;
      status|grant) command=$argument ;;
      -*)
        usage >&2
        return 2
        ;;
      *) names+=("$argument") ;;
    esac
  done
  if [[ $command == status && ${#names[@]} -gt 0 ]]
  then
    usage >&2
    return 2
  fi

  local via=app
  if ((use_shizuku))
  then
    if [[ $command == grant ]]
    then
      request_shizuku && shizuku_works && via=shizuku
    else
      shizuku_works && via=shizuku
    fi
  fi

  local state
  state=$(collect_"$via") || return 1
  if [[ $command == status ]]
  then
    printf 'Shizuku: %s\n' "$(app_shizuku refresh | tr '[:upper:]_' '[:lower:] ' | sed 's/^$/unknown (update the app)/')"
    [[ $via == app ]] && printf 'As reported by the TermuxPP app (Shizuku unavailable):\n'
    print_status "$state"
    return
  fi

  local todo
  todo=$(missing_entries "$state" "${names[@]}")
  if [[ -z $todo ]]
  then
    printf 'Nothing to grant.\n'
    print_status "$state"
    return
  fi

  local name entry_state kind detail failed=0
  if [[ $via == shizuku ]]
  then
    # Android grants background location only after foreground location.
    while read -r name entry_state kind detail
    do
      [[ $name == *BACKGROUND* ]] && continue
      grant_shizuku "$name" "$kind" "$detail" || { printf 'Could not grant %s\n' "$name" >&2; failed=1; }
    done <<<"$todo"
    while read -r name entry_state kind detail
    do
      [[ $name == *BACKGROUND* ]] || continue
      grant_shizuku "$name" "$kind" "$detail" || { printf 'Could not grant %s\n' "$name" >&2; failed=1; }
    done <<<"$todo"
  else
    local foreground=() background=() special=()
    while read -r name entry_state kind detail
    do
      if [[ $kind == special ]]
      then
        special+=("$name")
      elif [[ $name == *BACKGROUND* ]]
      then
        background+=("$detail")
      else
        foreground+=("$detail")
      fi
    done <<<"$todo"
    ((${#foreground[@]})) && ask_runtime "${foreground[@]}"
    # Android 11+ answers this request with the app's location page.
    ((${#background[@]})) && ask_runtime "${background[@]}"
    for name in "${special[@]}"
    do
      ask_special "$name"
    done
    sleep 2
  fi

  state=$(collect_"$via") || return 1
  print_status "$state" || failed=1
  return "$failed"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
