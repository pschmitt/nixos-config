zsh::autoload-dir strings
alias tolower="string::tolower"

alias toupper="string::toupper"

alias noemoji="string::remove-emojis"

alias noleadingemoji="string::remove-emojis"

alias nocolor="string::remove-escape-sequences"
alias string::nocolor="string::remove-escape-sequences"

alias t9="string::t9"

# Extract a section of text
# Example: resolvectl status | string::extract-section 'Link.*virbr0'
# Link 4 (virbr0)
#     Current Scopes: none
#          Protocols: -DefaultRoute +LLMNR +mDNS DNSOverTLS=opportunistic
#                     DNSSEC=yes/supported

falias string::is-ip url::is-an-ip-address
falias string::is-an-ip-address url::is-an-ip-address
falias string::is-ipv4 url::is-an-ipv4-address
falias string::is-an-ipv4-address url::is-an-ipv4-address
falias string::is-ipv6 url::is-an-ipv6-address
falias string::is-an-ipv6-address url::is-an-ipv6-address

alias redact="string::redact"
alias censor="string::redact"

alias indent="string::indent"
alias dedent="string::dedent"

alias extract-number="string::extract-number"
