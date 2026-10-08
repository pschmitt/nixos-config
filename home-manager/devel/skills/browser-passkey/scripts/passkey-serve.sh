#!/usr/bin/env bash

# Serve one rbw passkey, exactly once, as the credential object for the CDP
# WebAuthn.addCredential call. The browser fetches it (page.evaluate + fetch), so
# the private key never appears in a tool call or its output: the Playwright MCP
# tools echo the code they run, and their sandbox has no require/process/fetch.

usage() {
  cat <<EOF
Usage: $(basename "$0") [--bind ADDR] [--port PORT] [--rp-id RP_ID] ENTRY

Serves the passkey of the rbw entry ENTRY (name or uid) once, then exits.
Prints the one-time URL on the first line of stdout, e.g.
  http://172.17.0.1:18765/<token>

  --bind ADDR   address the browser can reach (default: the docker0 address,
                for the local playwright-browserless-fnuc; for rofl-13/14 use an
                address of this machine that they can reach)
  --port PORT   port (default: random)
  --rp-id ID    relying party to pick when the entry has several passkeys
                (default: the first one)

Run it in the background and read the URL from its output:
  $(basename "$0") ENTRY > /tmp/passkey.url &
EOF
}

docker_addr() {
  ip -4 -o addr show docker0 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4; exit }'
}

main() {
  local bind port="" rp_id="" entry=""

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --bind)
        bind="$2"
        shift 2
        ;;
      --port)
        port="$2"
        shift 2
        ;;
      --rp-id)
        rp_id="$2"
        shift 2
        ;;
      *)
        entry="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$entry" ]]
  then
    usage >&2
    return 2
  fi

  bind="${bind:-$(docker_addr)}"
  bind="${bind:-127.0.0.1}"

  rbw get "$entry" --raw | BIND="$bind" PORT="${port:-0}" RP_ID="$rp_id" python3 -c '
import base64, http.server, json, os, re, secrets, sys

data = json.load(sys.stdin)["data"]
creds = data.get("fido2_credentials") or []
if not creds:
    sys.exit("no passkey in this rbw entry")
want = os.environ["RP_ID"]
c = next((x for x in creds if want and x.get("rp_id") == want), creds[0])


def std(s):
    # base64url -> padded standard base64, as CDP expects
    return (s.replace("-", "+").replace("_", "/") + "=" * ((4 - len(s) % 4) % 4)) if s else ""


def cred_id(i):
    # Bitwarden stores UUID-style ids; CDP wants base64 of the raw bytes
    if re.fullmatch(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", i, re.I):
        return base64.b64encode(bytes.fromhex(i.replace("-", ""))).decode()
    return std(i)


body = json.dumps({
    "credentialId": cred_id(c["credential_id"]),
    "rpId": c["rp_id"],
    "privateKey": std(c["key_value"]),
    "userHandle": std(c.get("user_handle") or ""),
    "isResidentCredential": True,
    "signCount": 0,
    "backupEligibility": True,
    "backupState": True,
}).encode()
token = secrets.token_urlsafe(16)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/" + token:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)
        self.server.served = True

    def log_message(self, *args):
        pass


server = http.server.HTTPServer((os.environ["BIND"], int(os.environ["PORT"])), Handler)
server.served = False
server.timeout = 120
print("http://%s:%d/%s" % (os.environ["BIND"], server.server_port, token), flush=True)
while not server.served:
    server.handle_request()
    if not server.served and server.timeout and server.timeout > 0:
        # handle_request returns after the timeout without a request: give up
        break
'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
