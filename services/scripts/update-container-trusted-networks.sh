#!/usr/bin/env bash
set -eu

require_var()
{
  local var_name
  var_name=$1

  if [ "${!var_name-}" = "" ]
  then
    echo "${var_name} is required" >&2
    exit 1
  fi
}

copy_if_changed()
{
  local source
  local destination
  source=$1
  destination=$2

  if [ ! -e "$destination" ]
  then
    install -D -m 0644 "$source" "$destination"
    return 0
  fi

  if cmp -s "$source" "$destination"
  then
    return 1
  fi

  install -D -m 0644 "$source" "$destination"
  return 0
}

require_var "TRUSTED_HOSTS"

if [ "${NGINX_OUTPUT-}" = "" ] && [ "${AUTHELIA_OUTPUT-}" = "" ]
then
  echo "NGINX_OUTPUT or AUTHELIA_OUTPUT must be provided" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"

cleanup()
{
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM

addresses_tmp="$tmp_dir/addresses"
: >"$addresses_tmp"

nginx_tmp=""
if [ "${NGINX_OUTPUT-}" != "" ]
then
  nginx_tmp="$tmp_dir/nginx.conf"

  {
    printf '# Managed by container-services trusted host updater\n'
  } >"$nginx_tmp"
fi

authelia_tmp=""
if [ "${AUTHELIA_OUTPUT-}" != "" ]
then
  authelia_tmp="$tmp_dir/authelia.yml"

  {
    printf '# Managed by container-services trusted host updater\n'
    printf 'access_control:\n'
    printf '  networks:\n'

    if [ "${AUTHELIA_LOCAL_NETWORKS-}" != "" ]
    then
      printf '    - name: local\n'
      printf '      networks:\n'

      printf '%s\n' "$AUTHELIA_LOCAL_NETWORKS" |
        while IFS= read -r network
        do
          if [ "$network" != "" ]
          then
            printf '        - %s\n' "$network"
          fi
        done
    fi
  } >"$authelia_tmp"
fi

for host in $TRUSTED_HOSTS
do
  if [ "$nginx_tmp" != "" ]
  then
    printf '# Host: %s\n' "$host" >>"$nginx_tmp"
  fi

  current="$tmp_dir/current"
  : >"$current"

  for record_type in A AAAA
  do
    query="$tmp_dir/query-$record_type"

    if ! dig +short "$host" "$record_type" >"$query"
    then
      echo "failed to resolve $host ($record_type)" >&2
      exit 1
    fi

    if [ -s "$query" ]
    then
      cat "$query" >>"$current"
    fi
  done

  if [ ! -s "$current" ]
  then
    echo "no addresses resolved for $host" >&2
    exit 1
  fi

  sort -u "$current" >"$tmp_dir/current.sorted"

  while IFS= read -r address
  do
    if [ "$address" = "" ]
    then
      continue
    fi

    if [ "$nginx_tmp" != "" ]
    then
      printf 'allow %s;\n' "$address" >>"$nginx_tmp"
    fi

    printf '%s\n' "$address" >>"$addresses_tmp"
  done <"$tmp_dir/current.sorted"

  if [ "$nginx_tmp" != "" ]
  then
    printf '\n' >>"$nginx_tmp"
  fi

done

if [ ! -s "$addresses_tmp" ]
then
  echo "no addresses collected" >&2
  exit 1
fi

sort -u "$addresses_tmp" >"$tmp_dir/resolved"

if [ "$authelia_tmp" != "" ]
then
  printf '    - name: container-services-trusted\n' >>"$authelia_tmp"
  printf '      networks:\n' >>"$authelia_tmp"

  while IFS= read -r address
  do
    if [ "$address" = "" ]
    then
      continue
    fi

    suffix="/32"
    case "$address" in
      *:*)
        suffix="/128"
        ;;
    esac

    printf '        - %s%s\n' "$address" "$suffix" >>"$authelia_tmp"
  done <"$tmp_dir/resolved"
fi

nginx_changed=0
if [ "$nginx_tmp" != "" ] && [ "${NGINX_OUTPUT-}" != "" ]
then
  if copy_if_changed "$nginx_tmp" "$NGINX_OUTPUT"
  then
    nginx_changed=1
  fi
fi

authelia_changed=0
if [ "$authelia_tmp" != "" ] && [ "${AUTHELIA_OUTPUT-}" != "" ]
then
  if copy_if_changed "$authelia_tmp" "$AUTHELIA_OUTPUT"
  then
    authelia_changed=1
  fi
fi

if [ "$nginx_changed" -eq 1 ] && [ "${NGINX_SERVICE-}" != "" ]
then
  systemctl reload "$NGINX_SERVICE"
fi

if [ "$authelia_changed" -eq 1 ] && [ "${AUTHELIA_UNITS-}" != "" ]
then
  for unit in $AUTHELIA_UNITS
  do
    systemctl restart "$unit"
  done
fi
