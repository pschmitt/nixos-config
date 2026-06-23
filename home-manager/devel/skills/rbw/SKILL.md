---
name: rbw
description: >-
  Unlock rbw (Bitwarden CLI) via a Home Assistant phone notification.
  Use when rbw commands fail with "not unlocked", before calling
  rbw::get/rbw::find, or whenever the vault needs to be unlocked.
---

# rbw

Use this skill when rbw needs to be unlocked before a command can run.

## Check unlock status

```bash
rbw unlocked
```

Returns 0 if unlocked, non-zero if locked.

## Request unlock via Home Assistant

POST to the HA webhook to send an actionable notification to the phone.
On **Accept**, HA SSHes to the target host and pipes the master password
from HA secrets to `rbw unlock --stdin`.

```bash
curl -fsS -X POST "http://10.5.1.1:8123/api/webhook/rbw_unlock_request" \
  -H "Content-Type: application/json" \
  -d "{\"host\": \"${HOST:-fnuc}\", \"agent\": \"Claude\"}"
```

The `host` field is optional and defaults to `fnuc`. Known short names that
HA maps to SSH targets (`<name>.lan`): `fnuc`, `ge2`, `x13`, `gk4`.

The `agent` field is shown in the phone notification (defaults to `Claude`
if omitted).

## Poll for unlock

After triggering the webhook, poll until unlocked (2-minute timeout):

```bash
for i in $(seq 1 24); do
  rbw unlocked 2>/dev/null && break
  sleep 5
done
rbw unlocked || { echo "rbw unlock timed out"; exit 1; }
```

## Full unlock flow (copy-paste ready)

```bash
if ! rbw unlocked 2>/dev/null; then
  echo "Requesting rbw unlock on ${HOST:-fnuc} via Home Assistant..."
  curl -fsS -X POST "http://10.5.1.1:8123/api/webhook/rbw_unlock_request" \
    -H "Content-Type: application/json" \
    -d "{\"host\": \"${HOST:-fnuc}\", \"agent\": \"Claude\"}" || {
    echo "Failed to reach HA webhook" >&2; exit 1
  }
  echo "Waiting for Accept tap on phone (up to 2 minutes)..."
  for i in $(seq 1 24); do
    rbw unlocked 2>/dev/null && { echo "rbw unlocked"; break; }
    sleep 5
  done
  rbw unlocked || { echo "rbw unlock timed out"; exit 1; }
fi
```
