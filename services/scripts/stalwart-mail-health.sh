#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") DOMAIN DKIM_SELECTOR
EOF
}

dns_resolvers=(
  ""
  "1.1.1.1"
  "8.8.8.8"
)

dig_query() {
  local resolver=$1
  shift
  local resolver_args=()

  if [[ -n "${resolver}" ]]
  then
    resolver_args=("@${resolver}")
  fi

  dig +short +time=2 +tries=1 "${resolver_args[@]}" "$@"
}

check_tls() {
  local mode=$1
  local port=$2
  local starttls_args=()
  local output
  local _attempt

  if [[ -n "${mode}" ]]
  then
    starttls_args=("-starttls" "${mode}")
  fi

  # openssl's built-in STARTTLS negotiation occasionally races the server's
  # multi-line EHLO response ("Didn't find STARTTLS in server response,
  # trying anyway...") and aborts the handshake even though the server is
  # healthy. Retry a couple of times before treating it as a real failure.
  for _attempt in 1 2 3
  do
    if output="$(
      openssl s_client \
        "${starttls_args[@]}" \
        -brief \
        -connect "127.0.0.1:${port}" \
        -servername "${MAIL_HOST}" \
        -verify_hostname "${MAIL_HOST}" \
        -verify_return_error \
        </dev/null \
        2>&1
    )"
    then
      return 0
    fi
    sleep 1
  done

  printf 'TLS handshake failed on port %s:\n%s\n' "${port}" "${output}" >&2
  return 1
}

check_dns_txt() {
  local name=$1
  local expected=$2
  local resolver
  local record

  for resolver in "${dns_resolvers[@]}"
  do
    if ! record="$(dig_query "${resolver}" TXT "${name}" | tr -d '"')"
    then
      continue
    fi

    if [[ "${record}" == *"${expected}"* ]]
    then
      return 0
    fi
  done

  printf 'DNS TXT check failed for %s (expected %s)\n' "${name}" "${expected}" >&2
  return 1
}

check_dns_mx() {
  local resolver
  local record

  for resolver in "${dns_resolvers[@]}"
  do
    if ! record="$(dig_query "${resolver}" MX "${MAIL_DOMAIN}")"
    then
      continue
    fi

    if grep -Fq "mail.${MAIL_DOMAIN}." <<<"${record}"
    then
      return 0
    fi
  done

  printf 'DNS MX check failed for %s\n' "${MAIL_DOMAIN}" >&2
  return 1
}

check_smtp() {
  local response

  if ! exec 3<>"/dev/tcp/127.0.0.1/25"
  then
    printf 'Could not connect to SMTP port 25.\n' >&2
    return 1
  fi

  if ! IFS= read -r -t 10 response <&3
  then
    exec 3>&-
    printf 'SMTP port 25 did not send a greeting within 10 seconds.\n' >&2
    return 1
  fi

  if [[ "${response}" != 220* ]]
  then
    exec 3>&-
    printf 'SMTP port 25 sent an unexpected greeting: %s\n' "${response}" >&2
    return 1
  fi

  if ! printf 'EHLO %s\r\nQUIT\r\n' "${MAIL_HOST}" >&3
  then
    exec 3>&-
    printf 'SMTP port 25 rejected the EHLO write.\n' >&2
    return 1
  fi

  while IFS= read -r -t 10 response <&3
  do
    if [[ "${response}" == 250* ]]
    then
      exec 3>&-
      return 0
    fi
  done

  exec 3>&-
  printf 'SMTP port 25 did not return a successful EHLO response.\n' >&2
  return 1
}

run_check() {
  local label=$1
  shift

  printf '%s: ' "${label}"
  if "$@"
  then
    printf 'OK\n'
  else
    printf 'FAILED\n'
    return 1
  fi
}

main() {
  if [[ $# -ne 2 ]]
  then
    usage >&2
    return 2
  fi

  local MAIL_DOMAIN=$1
  local DKIM_SELECTOR=$2
  local MAIL_HOST="mail.${MAIL_DOMAIN}"

  run_check "ACME service active" \
    systemctl --quiet is-active "acme-${MAIL_HOST}.service"
  run_check "Certificate valid for 5 days" openssl x509 \
    -checkend 432000 \
    -noout \
    -in "/var/lib/acme/${MAIL_HOST}/fullchain.pem"

  run_check "SMTP 25" check_smtp
  run_check "Implicit TLS 465" check_tls "" 465
  run_check "SMTP STARTTLS 587" check_tls "smtp" 587
  run_check "Implicit TLS 993" check_tls "" 993
  run_check "IMAP STARTTLS 143" check_tls "imap" 143

  run_check "DNS MX" check_dns_mx
  run_check "DNS SPF" check_dns_txt "${MAIL_DOMAIN}" "v=spf1"
  run_check "DNS DMARC" check_dns_txt "_dmarc.${MAIL_DOMAIN}" "v=DMARC1"
  run_check "DNS DKIM version" check_dns_txt \
    "${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}" "v=DKIM1"
  run_check "DNS DKIM public key" check_dns_txt \
    "${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}" "p="

  printf 'All Stalwart mail health checks passed.\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
