complete -c termuxpp-adb-ssh-proxy -f
complete -c termuxpp-adb-ssh-proxy -s h -l help -d 'Show help'
complete -c termuxpp-adb-ssh-proxy -l serial -x -a '(termuxpp-adb-shell --list-aliases 2>/dev/null)' -d 'ADB serial or alias'
complete -c termuxpp-adb-ssh-proxy -l devices-config -rF -d 'Device configuration'
complete -c termuxpp-adb-ssh-proxy -l port -x -d 'Device SSH port'
complete -c termuxpp-adb-ssh-proxy -l credential-dir -x -a '(__fish_complete_directories)' -d 'mTLS credential directory'
complete -c termuxpp-adb-ssh-proxy -l no-start -d 'Do not start SSH'
complete -c termuxpp-adb-ssh-proxy -l probe-timeout -x -d 'Listener probe timeout'
complete -c termuxpp-adb-ssh-proxy -l start-timeout -x -d 'Daemon launch timeout'
complete -c termuxpp-adb-ssh-proxy -l ready-timeout -x -d 'Listener readiness timeout'
# vim: set sw=2 sts=2 et:
