# Repairs and stale warnings

The user often reports "I see a repair / dashboard warning for X". Check the repair list before
guessing.

## List the active repairs

```
zsh -lc 'zhj hass-cli raw ws repairs/list_issues' \
  | yq -r '.result.issues[] | select(.ignored|not) | [.domain,.issue_id,.severity,.is_fixable] | @tsv'
```

`hass-cli raw ws` prints YAML. Ignored issues are old noise; an empty result means nothing is
active.

## Our custom integrations

Authored in `/mnt/ha/custom_components-local/homeassistant-<name>/` (git submodules, see
`/mnt/ha/AGENTS.md`). Repairs raised by them live in the integration's `repairs.py`. Fix the
source there, not under `custom_components/`.

| Symptom | What we know |
|---|---|
| hrworks "session expired" repair that is not true | The worker raises `session_expired` on a 403 or a late login redirect (`hrworks_worker/portal.py`). Reloading the config entry usually clears it. A retry for timed-out logins was added (commits `85e1ad5`, `88d9e50`); if it still happens, look at the worker log and the browser-daemon `hrworks` profile first. Never type credentials; see the `hrworks` skill. |
| fints `ing_reauth_required` | A real 2FA reauth, completed from the repair flow. Check that the fints settings page shows the service as failed too. |
| "Config flow could not be loaded: 500" when opening a repair | The integration's repair or flow module broke. Read `ha core logs` through `grep`, fix the module, restart HA. |
| Offline-device or battery warnings stay after the cause is gone | Check the entity behind the card first, then the integration `homeassistant-offline-devices` ignore list (the user asked for ignoring known-offline devices). |

## Reload one integration

```
zsh -lc 'zhj hass::config-entries --domain hrworks'     # entry id, key names only
zsh -lc 'zhj hass-cli service call homeassistant.reload_config_entry --arguments entry_id=<id>'
```

Reloading is the first, cheap step. If the repair returns, find the cause; do not keep reloading.

## Restarts

A restart takes about 90 s when healthy. Rules about startup time are in `/mnt/ha/AGENTS.md`.
When the user wants a restart postponed (for example to keep a counter intact), use the
`restart_home_assistant_tonight` or `_later` scripts instead of restarting at once.
