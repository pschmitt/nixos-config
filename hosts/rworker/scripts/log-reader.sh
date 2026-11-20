printf -v empty_argument '%s%s' "'" "'"
read -r -a request <<< "${SSH_ORIGINAL_COMMAND:-}"
[[ ${request[0]:-} == bash && ${request[1]:-} == -s && ${request[2]:-} == -- ]] || exit 126
case "${request[3]:-}" in
  jobs)
    [[ ${#request[@]} -eq 4 ]] || exit 126
    cat >/dev/null
    exec bash "$RWORKER_JOBS_SCRIPT" jobs
    ;;
  log-cache-tail)
    [[ ${#request[@]} -eq 8 ]] || exit 126
    stamp=${request[6]}
    [[ "$stamp" != "$empty_argument" ]] || stamp=""
    cat >/dev/null
    exec bash "$RWORKER_LOG_EXPORT_SCRIPT" log-cache-tail "${request[4]}" "${request[5]}" "$stamp" "${request[7]}"
    ;;
  *) exit 126 ;;
esac
