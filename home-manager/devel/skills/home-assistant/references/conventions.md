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
