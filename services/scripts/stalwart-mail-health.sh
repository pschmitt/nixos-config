#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") DOMAIN DKIM_SELECTOR
EOF
}

check_tls() {
  local mode=$1
  local port=$2
  local starttls_args=()

  if [[ -n "${mode}" ]]
  then
    starttls_args=("-starttls" "${mode}")
  fi

  openssl s_client \
    "${starttls_args[@]}" \
    -connect "127.0.0.1:${port}" \
    -servername "${MAIL_HOST}" \
    -verify_hostname "${MAIL_HOST}" \
    -verify_return_error \
    </dev/null \
    >/dev/null \
    2>&1
}

check_dns_txt() {
  local name=$1
  local expected=$2
  local record

  record="$(dig +short TXT "${name}" | tr -d '"')"
  [[ "${record}" == *"${expected}"* ]]
}

check_dns_mx() {
  dig +short MX "${MAIL_DOMAIN}" | grep -Fq "mail.${MAIL_DOMAIN}."
}

check_smtp() {
  local response

  exec 3<>"/dev/tcp/127.0.0.1/25" || return 1

  if ! IFS= read -r -t 10 response <&3
  then
    exec 3>&-
    return 1
  fi

  if [[ "${response}" != 220* ]]
  then
    exec 3>&-
    return 1
  fi

  if ! printf 'EHLO %s\r\nQUIT\r\n' "${MAIL_HOST}" >&3
  then
    exec 3>&-
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
  return 1
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

  systemctl --quiet is-active "acme-${MAIL_HOST}.service"
  openssl x509 \
    -checkend 432000 \
    -noout \
    -in "/var/lib/acme/${MAIL_HOST}/fullchain.pem" \
    >/dev/null

  check_smtp
  check_tls "" 465
  check_tls "smtp" 587
  check_tls "" 993
  check_tls "imap" 143

  check_dns_mx
  check_dns_txt "${MAIL_DOMAIN}" "v=spf1"
  check_dns_txt "_dmarc.${MAIL_DOMAIN}" "v=DMARC1"
  check_dns_txt "${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}" "v=DKIM1"
  check_dns_txt "${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}" "p="
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
