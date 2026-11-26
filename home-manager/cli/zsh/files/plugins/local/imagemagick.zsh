# ImageMagick
(( $+commands[magick] )) || return 0

alias img::open="img::cat"
alias img::display="img::cat"

alias img::density='img::size --density'
alias img::resolution='img::size --density'

alias img::auto-crop="img::crop-auto"
alias img::crop="img::crop-auto"

alias img::remove-bg="img::remove-background"
