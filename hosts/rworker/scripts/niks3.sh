dir=/run/rworker-niks3
if [[ -r "$dir/token" && -z "${NIKS3_AUTH_TOKEN_FILE:-}" ]]
then
  export NIKS3_AUTH_TOKEN_FILE="$dir/token"
fi
if [[ -r "$dir/server-url" && -z "${NIKS3_SERVER_URL:-}" ]]
then
  NIKS3_SERVER_URL=$(< "$dir/server-url")
  export NIKS3_SERVER_URL
fi
exec niks3 "$@"

# vim: set ft=sh et ts=2 sw=2 :
