function __termuxpp_adb_shell_serials
  adb devices 2>/dev/null | string match -r '^([^\s]+)\s+device$' | string match -v -r '\s'
end

for cmd in termuxpp-adb-shell termuxpp-adb-shell.py
  complete -c $cmd -f
  complete -c $cmd -s h -l help -d 'Show help'
  complete -c $cmd -l serial -r -a '(__termuxpp_adb_shell_serials)' -d 'ADB device serial'
  complete -c $cmd -l mode -r -a 'auto mtls run-as' -d 'Shell transport'
  complete -c $cmd -l shell -r -a 'bash zsh fish sh' -d 'Override configured login shell'
  complete -c $cmd -l completions -r -a 'bash zsh fish' -d 'Print shell integration'
  complete -c $cmd -l provision -d 'Enroll mTLS client'
  complete -c $cmd -l list-authorizations -d 'List approved certificates'
  complete -c $cmd -l revoke -r -d 'Revoke certificate by SHA256 fingerprint'
  complete -c $cmd -l name -r -d 'Client display name'
  complete -c $cmd -l credential-dir -r -a '(__fish_complete_directories)' -d 'Private mTLS credential directory'
end
