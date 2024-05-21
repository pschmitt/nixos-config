#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") [--check] [--force] [--missing] TARGET_HOST"
}

echo_info() {
  echo -e "\e[1m\e[34mINF\e[0m $*" >&2
}

echo_success() {
  echo -e "\e[1m\e[32mOK\e[0m $*" >&2
}

echo_warning() {
  [[ -n "$NO_WARNING" ]] && return 0
  echo -e "\e[1m\e[33mWRN\e[0m $*" >&2
}

echo_error() {
  echo -e "\e[1m\e[31mERR\e[0m $*" >&2
}

gen_ssh_host_keys() {
  local target_host="$1" yaml
  local key_type tmpfile

  for key_type in rsa ed25519
  do
    tmpfile="$(mktemp --dry-run)"
    ssh-keygen -t "$key_type" -N "" -C "root@${target_host}" -f "$tmpfile" &>/dev/null

    privkey=$(cat "$tmpfile")
    pubkey=$(cat "${tmpfile}.pub")

    yaml=$(pubkey="$pubkey" privkey="$privkey" key_type="$key_type" yq -er '
      .ssh.host_keys[strenv(key_type)].privkey = strenv(privkey) |
      .ssh.host_keys[strenv(key_type)].pubkey = strenv(pubkey)
    ' <<< "$yaml")

    # Display public key
    echo_info "$pubkey"
    rm -f "$tmpfile" "${tmpfile}.pub"
  done

  echo "$yaml"
}

gen_luks_passphrase() {
  pwgen 120 1 | tr -d '\n'
}

gen_dummy_secret() {
  echo -n "changeme"
}

luks_passphrase_yaml() {
  passph="$(gen_luks_passphrase)" \
    yq -ner '.luks.root = strenv(passph)'
}

main() {
  FORCE="${FORCE:-}"
  CHECK="${CHECK:-}"
  MISSING="${MISSING:-}"

  local args=()

  while [[ -n "$*" ]]
  do
    case "$1" in
      -f|--force)
        FORCE=1
        shift
        ;;
      -c|--check)
        CHECK=1
        shift
        ;;
      -m|--missing)
        MISSING=1
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  set -- "${args[@]}"

  local target_host="$1"

  if [[ -z "$target_host" ]]
  then
    usage
    exit 0
  fi

  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  SOPS_FILE="../hosts/${target_host}/secrets.sops.yaml"
  SOPS_LUKS_FILE="../hosts/${target_host}/luks.sops.yaml"

  if [[ -e "$SOPS_FILE" && -z "$FORCE" ]]
  then
    echo_warning "sops file $SOPS_FILE already exists"
    exit 1
  fi

  if [[ -e "$SOPS_LUKS_FILE" && -z "$FORCE" ]]
  then
    echo_warning "sops file $SOPS_LUKS_FILE already exists"
    exit 1
  fi

  mkdir -p "$(dirname "$SOPS_FILE")"

  # Create LUKS passphrase
  sops --encrypt --input-type yaml \
    <(luks_passphrase_yaml) \
    > "$SOPS_LUKS_FILE"

  local cleartext
  cleartext=$(gen_ssh_host_keys "$target_host")

  # Append dummy secrets
  cleartext=$(yq -er '
    .mail.gmail = "changeme" |
    .mail.heimat-dev = "changeme"
    ' <<< "$cleartext")

  # TODO --filename-override is not supported in sops 3.8.1
  # shellcheck disable=SC2094
  # sops --encrypt --input-type yaml \
  #   --filename-override "$SOPS_FILE" \
  #   <(echo "$cleartext") \
  #   > "$SOPS_FILE"

  sops --encrypt --input-type yaml \
    <(echo "$cleartext") \
    > "$SOPS_FILE"

  # Force a rekey (our host might need access to shared secrets)
  ./sops-config-gen.sh
  ./sops-update-keys.sh
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
