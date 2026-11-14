#!/usr/bin/env bash
# Fake OpenStack metadata service for the boot test. QEMU's guestfwd runs
# this once per connection to 169.254.169.254:80, with the HTTP request on
# stdin and the response expected on stdout.

respond() {
  local status="$1" body="$2"
  printf 'HTTP/1.0 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
    "$status" "${#body}" "$body"
}

main() {
  local method path _version line
  read -r method path _version || return 0
  # Drain the headers.
  while read -r line
  do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && break
  done

  case "$method $path" in
    "GET /openstack/latest/meta_data.json")
      respond "200 OK" '{"name": "test-worker", "uuid": "00000000-0000-4000-8000-000000000000", "availability_zone": "boot-test", "meta": {"nixbot-worker": "adhoc", "owner": "test@boot-test", "setup_key_id": "must-not-show"}}'
      ;;
    "GET /openstack/latest/user_data")
      respond "200 OK" '{"netbird_setup_key": "00000000-0000-0000-0000-000000000000", "agent_authorized_keys": []}'
      ;;
    *)
      respond "404 Not Found" '{}'
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
