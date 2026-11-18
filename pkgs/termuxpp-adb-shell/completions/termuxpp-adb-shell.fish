function __termuxpp_adb_shell_serials
  adb devices 2>/dev/null | string match -r '^([^\s]+)\s+device$' | string match -v -r '\s'
  set -l words (commandline -opc)
  test (count $words) -gt 0; and $words[1] --list-aliases 2>/dev/null
end

function __termuxpp_adb_shell_command
  contains -- -- (commandline -opc)
end

function __termuxpp_adb_shell_command_name
  set -l words (commandline -opc)
  set -l separator (contains -i -- -- $words)
  test -n "$separator"; and test (count $words) -eq $separator
end

for cmd in termuxpp-adb-shell termuxpp-adb-shell.py
  complete -c $cmd -f
  complete -c $cmd -n __termuxpp_adb_shell_command -F
  complete -c $cmd -n __termuxpp_adb_shell_command_name -a '(__fish_complete_command)'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -s h -l help -d 'Show help'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l serial -r -a '(__termuxpp_adb_shell_serials)' -d 'ADB device serial or alias'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l devices-config -r -F -d 'Private JSON device alias configuration'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l list-aliases -d 'List configured device aliases'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l mode -r -a 'auto mtls run-as' -d 'Shell transport'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l outer -d 'Use the native TermuxPP environment'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l shell -r -a 'bash zsh fish sh' -d 'Override configured login shell'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l completions -r -a 'bash zsh fish' -d 'Print shell integration'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l provision -d 'Enroll mTLS client'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l list-authorizations -d 'List approved certificates'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l revoke -r -d 'Revoke certificate by SHA256 fingerprint'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l name -r -d 'Client display name'
  complete -c $cmd -n 'not __termuxpp_adb_shell_command' -l credential-dir -r -a '(__fish_complete_directories)' -d 'Private mTLS credential directory'
end
