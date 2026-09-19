main() {
  local attempt

  for ((attempt = 0; attempt < 30; attempt++))
  do
    if xdpyinfo >/dev/null 2>&1
    then
      exec x11vnc -display "$DISPLAY" -auth "$XAUTHORITY" \
        -listen 127.0.0.1 -rfbport 5907 -forever -shared -nopw
    fi
    sleep 1
  done

  printf 'Staging browser display did not become ready within 30 seconds\n' >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
