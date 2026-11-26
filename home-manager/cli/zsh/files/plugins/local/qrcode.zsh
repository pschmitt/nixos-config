# qrencode
(( $+commands[qrencode] )) || return

zsh::autoload-dir qrcode

alias qrcode::encode=qrcode
alias qrcode::create=qrcode

alias qrcode::decode=qrdecode
alias qrcode::read=qrdecode

# vim: set ft=zsh et ts=2 sw=2 :
