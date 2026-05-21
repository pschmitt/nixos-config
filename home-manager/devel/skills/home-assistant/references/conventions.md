# Home Assistant Conventions

## Scope

This repository contains the Home Assistant configuration for the `hv` VM.
Keep changes narrow and avoid unrelated formatting churn in YAML-heavy files.
On most of your hosts, the Home Assistant filesystem is mounted at `/mnt/hass`.

## Home Assistant Access

- UI: `http://10.5.1.1:8123`
- External UI: `https://ha.brkn.lol`
- Prefer `hass-cli` for shell-driven inspection and API calls.
- If authentication is needed, prefer `zhj hass-cli`.
- If a Home Assistant token is needed, use `zhj hass::secrets-gu5a`.
- `zhj hass::secrets-gu5a` outputs the server URL and token as a
  space-separated pair.

Example:

```sh
hass-cli raw ws lovelace/config --json='{"force": false, "url_path": "simple-dashboard"}'
```

## VM And Host Access

- `ssh -p 22 hv` connects to the Home Assistant shell container.
- `ssh -p 22222 hv` connects to the Home Assistant host system.
- The Home Assistant VM runs on `fnuc`.
- If you are not already on `fnuc`, use `ssh f` first and then connect to `hv`.

## Working Conventions

- Validate Home Assistant changes before and after editing when practical.
- Prefer focused edits in `config.d/` and avoid rewriting generated or
  unrelated sections.
- Expect unrelated local changes in this repo; do not revert them unless
  explicitly asked.
- Once a discrete feature or task is done, ask the user whether to create a
  focused commit and push it.
- If a change depends on a git submodule, keep the submodule itself current and
  commit the submodule update intentionally rather than leaving it drifting.
- For template sensors and frontend-facing text, prefer output that is easy to
  render directly in Lovelace.
- Avoid writing directly into `.storage/`. Treat that as a last resort only,
  and require explicit user confirmation before making any change there.

## Lovelace / Dashboard Editing

Dashboard configs in "storage" (UI-managed) mode live at:

```
/mnt/hass/.storage/lovelace.<url-slug>
```

The `<url-slug>` uses underscores (`lovelace.main_dashboard` for
`url_path: "main-dashboard"`). Find the slug-to-url_path mapping in
`/mnt/hass/.storage/lovelace_dashboards`.

**Direct `.storage/lovelace.*` editing is the correct approach** when the user
explicitly asks to change a dashboard — no separate confirmation is needed.
Parse with Python's `json` module, mutate, and write back:

```python
import json
with open('/mnt/hass/.storage/lovelace.main_dashboard') as f:
    dash = json.load(f)
# … mutate dash['data']['config'] …
with open('/mnt/hass/.storage/lovelace.main_dashboard', 'w') as f:
    json.dump(dash, f, indent=2)
```

**Applying changes live (no restart needed):** writing the file does not
update HA's in-memory cache, and `lovelace/config` with `force: true` also
does not work (HA's `Store` class returns its own `_data` cache regardless).
Push the change live by sending `lovelace/config/save` over WebSocket with
the full updated config — use this self-contained Python snippet (stdlib only):

```python
import json, socket, os, struct, base64

with open('/mnt/hass/.storage/lovelace.main_dashboard') as f:
    config = json.load(f)['data']['config']

# read URL TOKEN < <(zsh -lc 'zhj hass::secrets-gu5a')
HOST, PORT, TOKEN = "10.5.1.1", 8123, "<token>"

def ws_send(s, payload):
    data = json.dumps(payload).encode()
    frame = bytearray([0x81])
    if len(data) < 126:     frame.append(0x80 | len(data))
    elif len(data) < 65536: frame.append(0x80 | 126); frame.extend(struct.pack(">H", len(data)))
    else:                   frame.append(0x80 | 127); frame.extend(struct.pack(">Q", len(data)))
    mask = os.urandom(4); frame.extend(mask)
    frame.extend(bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
    s.sendall(bytes(frame))

def ws_recv(s):
    h = b""
    while len(h) < 2: h += s.recv(2 - len(h))
    ln = h[1] & 0x7f
    if ln == 126:
        e = b""; while len(e) < 2: e += s.recv(2 - len(e)); ln = struct.unpack(">H", e)[0]
    elif ln == 127:
        e = b""; while len(e) < 8: e += s.recv(8 - len(e)); ln = struct.unpack(">Q", e)[0]
    d = b""
    while len(d) < ln:
        c = s.recv(min(65536, ln - len(d)))
        if not c: break
        d += c
    return json.loads(d.decode()) if d else {}

s = socket.create_connection((HOST, PORT), timeout=30)
ws_key = base64.b64encode(os.urandom(16)).decode()
s.sendall(
    f"GET /api/websocket HTTP/1.1\r\nHost: {HOST}:{PORT}\r\n"
    f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {ws_key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    .encode()
)
resp = b""
while b"\r\n\r\n" not in resp: resp += s.recv(4096)
ws_recv(s)  # auth_required
ws_send(s, {"type": "auth", "access_token": TOKEN})
assert ws_recv(s).get("type") == "auth_ok"
ws_send(s, {"id": 1, "type": "lovelace/config/save",
            "url_path": "main-dashboard", "config": config})
print(ws_recv(s))  # {"success": true, ...}
s.close()
```

**Verifying changes:** `hass-cli raw ws lovelace/config` truncates output for
large dashboards (~3 400 lines). Verify the storage file directly with Python
instead of relying on hass-cli output.
