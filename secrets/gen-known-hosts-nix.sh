#!/usr/bin/env bash
set -euo pipefail

# Generate a Nix attrset mapping host -> { ed25519 = "..."; rsa = "..."; }
# from SOPS host secrets and write it next to ssh.nix so it can be imported.

GIT_ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1; pwd -P)"
DEST="$GIT_ROOT/common/global/ssh-hosts.generated.nix"

echo "Regenerating $DEST" >&2

{
  echo '{'

  shopt -s nullglob
  for SOPS_FILE in "${GIT_ROOT}"/hosts/*/secrets.sops.yaml
  do
    host_dir="$(dirname "$SOPS_FILE")"
    host="$(basename "$host_dir")"

    # Extract pubkeys; allow missing silently
    ed25519="$(sops --decrypt --extract '["ssh"]["host_keys"]["ed25519"]["pubkey"]' "$SOPS_FILE" 2>/dev/null || true)"
    rsa="$(sops --decrypt --extract '["ssh"]["host_keys"]["rsa"]["pubkey"]' "$SOPS_FILE" 2>/dev/null || true)"

    # Skip hosts without any pubkeys
    if [[ -z "$ed25519" && -z "$rsa" ]]
    then
      echo "SKIP host $host without any pubkeys" >&2
      continue
    fi

    # Write the mapping for this host; only include keys that exist
    echo "  \"$host\" = {"
    if [[ -n "$ed25519" ]]
    then
      printf '    ed25519 = "%s";\n' "$ed25519"
    fi

    if [[ -n "$rsa" ]]
    then
      printf '    rsa = "%s";\n' "$rsa"
    fi

    echo "  };"
  done

  echo '}'
} >"$DEST"

  echo "Wrote $DEST" >&2
