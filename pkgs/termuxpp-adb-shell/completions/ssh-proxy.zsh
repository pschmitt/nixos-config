#compdef termuxpp-adb-ssh-proxy

_arguments \
  '(-h --help)'{-h,--help}'[Show help]' \
  '--serial[ADB serial or alias]:device:($(termuxpp-adb-shell --list-aliases 2>/dev/null))' \
  '--devices-config[Device configuration]:file:_files' \
  '--port[Device SSH port]:port:' \
  '--credential-dir[mTLS credential directory]:directory:_directories' \
  '--no-start[Do not start SSH]' \
  '--probe-timeout[Listener probe timeout]:seconds:' \
  '--start-timeout[Daemon launch timeout]:seconds:' \
  '--ready-timeout[Listener readiness timeout]:seconds:'
# vim: set sw=2 sts=2 et:
