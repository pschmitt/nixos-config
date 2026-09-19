main() {
  local password
  password="$(<"${CREDENTIALS_DIRECTORY}/password")"
  # Rebuild only the runtime auth database; never write credentials to the store.
  install -m 0600 /dev/null "${RUNTIME_DIRECTORY}/pureftpd.passwd"
  printf '%s\n%s\n' "$password" "$password" |
    pure-pw useradd reolink -f "${RUNTIME_DIRECTORY}/pureftpd.passwd" \
      -u 1000 -g 1000 -d "$REOLINK_DATA_DIR" >/dev/null
  pure-pw mkdb "${RUNTIME_DIRECTORY}/pureftpd.pdb" \
    -f "${RUNTIME_DIRECTORY}/pureftpd.passwd"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
