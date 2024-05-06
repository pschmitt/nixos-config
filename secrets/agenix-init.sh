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

all_agenix_secrets() {
  sed -nr 's#.*"([^"]+)".*#\1#p' ./secrets.nix
}

agenix_secrets() {
  local hostname="$1"
  all_agenix_secrets | grep -E "^${hostname}/"
}

gen_ssh_key() {
  local key_type="$1"
  local target_host="$2"
  local secret_file="${target_host}/ssh_host_${key_type}_key"
  local tmpfile
  tmpfile="$(mktemp --dry-run)"
  if [[ -e "$secret_file" ]] && [[ -z "$force" ]]
  then
    echo_warning "Secret $secret_file already exists: SKIP"
    return 0
  fi
  ssh-keygen -t "$key_type" -N "" -C "root@${target_host}" -f "$tmpfile"
  agenix -e "${secret_file}.age" <"$tmpfile"
  agenix -e "${secret_file}.pub.age" <"${tmpfile}.pub"
  rm -f "$tmpfile" "${tmpfile}.pub"
}

gen_ssh_host_keys() {
  local target_host="$1"

  local rc=0
  local key_type tmpfile secret
  local pubkeyfile privkeyfile
  for key_type in rsa ed25519
  do
    secret="${target_host}/ssh_host_${key_type}_key"
    privkeyfile="${secret}.age"
    pubkeyfile="${secret}.pub.age"

    if [[ -e "$privkeyfile" || -e "$pubkeyfile" ]] && [[ -z "$FORCE" ]]
    then
      if [[ -n "$CHECK" ]]
      then
        if [[ -e "$privkeyfile" ]]
        then
          echo_success "$key_type private key exists at $privkeyfile"
        else
          rc=1
          echo_error "Missing $key_type private key at $privkeyfile"
        fi
        if [[ -e "$pubkeyfile" ]]
        then
          echo_success "$key_type public key exists at $pubkeyfile"
        else
          echo_error "Missing $key_type publicate key at $pubkeyfile"
          rc=1
        fi

        continue
      else
        echo_warning "$secret already exists. Use --force to overwrite"
        echo_warning "--force overwrites *ALL* secrets for $target_host"
      fi
      return 1
    fi

    tmpfile="$(mktemp --dry-run)"
    ssh-keygen -t "$key_type" -N "" -C "root@${target_host}" -f "$tmpfile" &>/dev/null

    if ! agenix -e "$privkeyfile" <"$tmpfile"
    then
      rc=1
      echo_error "Failed to save $privkeyfile"
    else
      echo_success "Generated SSH $key_type private key $privkeyfile"
    fi

    if ! agenix -e "$pubkeyfile" <"${tmpfile}.pub"
    then
      rc=1
      echo_error "Failed to save $pubkeyfile"
    else
      echo_success "Generated SSH $key_type public key $pubkeyfile"
    fi

    # Display public key
    echo_info "$(cat "${tmpfile}.pub")"
    rm -f "$tmpfile" "${tmpfile}.pub"
  done

  return "$rc"
}

gen_luks_passphrase() {
  pwgen 120 1 | tr -d '\n'
}

gen_dummy_secret() {
  echo -n "changeme"
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

  mapfile -t AGENIX_SECRETS < <(agenix_secrets "$target_host" | \
    grep -vE 'ssh_host_.*_key*')

  if [[ "${AGENIX_SECRETS[*]}" == "" ]]
  then
    echo "No secrets found for $target_host" >&2
    echo "Please edit secrets.nix to add secrets for $target_host" >&2
    exit 1
  fi

  mkdir -p "$target_host"
  if ! gen_ssh_host_keys "$target_host"
  then
    if [[ -z "$MISSING" ]]
    then
      exit 1
    fi
  fi

  local secret value
  for secret in "${AGENIX_SECRETS[@]}"
  do
    if [[ -n "$CHECK" ]]
    then
      if [[ -e "$secret" ]]
      then
        echo_success "Secret $secret exists"
      else
        echo_error "Secret $secret does not exist"
      fi
      continue
    fi

    if [[ -e "$secret" ]]
    then
      if [[ -z "$FORCE" ]]
      then
        echo_warning "Secret $secret already exists: SKIP"
        continue
      else
        echo_warning "Overwriting secret $secret"
      fi
    fi

    case "$secret" in
      *luks-passphrase*)
        value=$(gen_luks_passphrase)
        ;;
      *ssh_host_*)
        echo_info "Skipping SSH host key $secret"
        continue
        ;;
      *)
        value=$(gen_dummy_secret)
        ;;
    esac

    echo_info "Storing secret \e[34m$secret\e[0m - value: \e[36m$value\e[0m" >&2
    agenix -e "$secret" <<< "$value"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
