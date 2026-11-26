# ImageMagick
(( $+commands[magick] )) || return 0

zsh::autoload-dir imagemagick

alias img::open="img::cat"
alias img::display="img::cat"

img::size() {
  local usage="usage: $0 [-n] [--width|--height] FILE"
  local help output nonewline
  zparseopts -D -E -K -- \
    {h,-help}=help \
    {w,-width}=output \
    {H,-height}=output \
    {x,-x-resolution}=output \
    {y,-y-resolution}=output \
    {d,-density}=output \
    {n,-no-newline,-nonewline}=nonewline

  if [[ -n "$help" ]]
  then
    echo "$usage"
    return 0
  fi

  local input="${1:--}"

  local fmt="%wx%h" # default fmt: width x height

  case "$output" in
    -w|*width*)
      fmt="%w"
      ;;
    -H|*height*)
      fmt="%h"
      ;;
    -x|*x-resolution*|-d|*density*)
      fmt="%x"
      ;;
    -y|*y-resolution*)
      fmt="%y"
      ;;
  esac

  [[ -z $nonewline ]] && fmt="${fmt}\\n"

  magick identify -format "$fmt" "$input"
}

alias img::density='img::size --density'
alias img::resolution='img::size --density'

alias img::auto-crop="img::crop-auto"
alias img::crop="img::crop-auto"

alias img::remove-bg="img::remove-background"
