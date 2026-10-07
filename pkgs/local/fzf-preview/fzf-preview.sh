
# see also: https://github.com/junegunn/fzf/blob/master/bin/fzf-preview.sh

# set -x

usage() {
  echo "Usage: $0 FILE[:LINENO][:IGNORED]"
}

mimetype() {
  file --dereference --mime-type --brief -- "$1" 2>/dev/null
}

has() {
  command -v "$1" &> /dev/null
}

is_kitty() {
  [[ -n "$KITTY_WINDOW_ID" ]]
}

is_ghostty() {
  [[ -n "$GHOSTTY_BIN_DIR" ]]
}

is_termux() {
  has termux-info
}

in_tmux() {
  [[ -n "$TMUX" ]]
}

bat::bin-path() {
  local bat_bin

  if has bat
  then
    bat_bin="bat"
  # Sometimes bat is installed as batcat.
  elif has batcat
  then
    bat_bin="batcat"
  fi

  [[ -z "$bat_bin" ]] && return 1

  echo "$bat_bin"
}

preview::binary() {
  echo "WARNING. Binary file: '$1'"
}

meta::get-preview-window-dimensions() {
  local dimensions="${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}"

  if [[ $dimensions = x ]]
  then
    dimensions=$(stty size < /dev/tty | awk '{ print $2 "x" $1 }')
  elif ! [[ $KITTY_WINDOW_ID ]] && \
      ((
        FZF_PREVIEW_TOP + FZF_PREVIEW_LINES
        ==
        $(stty size < /dev/tty | awk '{ print $1 }')
      ))
  then
    # Avoid scrolling issue when the Sixel image touches the bottom of the screen
    # * https://github.com/junegunn/fzf/issues/2544
    dimensions="${FZF_PREVIEW_COLUMNS}x$((FZF_PREVIEW_LINES - 1))"
  fi

  echo "$dimensions"
}

preview::image() {
  local file="$1"

  local dimensions
  dimensions="$(meta::get-preview-window-dimensions)"

  if is_kitty || { is_ghostty && has kitten; }
  then
    kitten icat \
      --clear \
      --transfer-mode=memory \
      --stdin=no \
      --unicode-placeholder \
      --align=center \
      --place="${dimensions}@0x0" \
      -- "$file" | sed '$d' | sed $'$s/$/\e[m/'
    return "$?"
  fi

  # chafa is kinda meh in tmux
  # https://github.com/hpjansson/chafa/issues/218
  if has chafa && ! in_tmux
  then
    chafa --clear --size "$dimensions" "$file"
    return "$?"
  fi

  if has termimage
  then
    termimage --size "$dimensions" "$file"
    return "$?"
  fi

  echo "WARN No image preview program available" >&2
  return 1
}

preview::directory() {
  if has eza
  then
    eza \
      --color=always \
      --icons=always \
      --header \
      --tree \
      --group-directories-first \
      --long \
      --almost-all \
      "$1"
    return "$?"
  fi

  if has lsd
  then
    lsd -1 \
      --color=always \
      --icon=always \
      --almost-all \
      --group-directories-first \
      --recursive \
      --depth 2 \
      "$1"
    return "$?"
  fi

  if has tree
  then
    tree -C \
      -Fax \
      --noreport \
      --filelimit 100 \
      --dirsfirst \
      "$1"
    return "$?"
  fi

  # fall back to ls
  ls -1 \
    --color=always \
    --indicator-style=slash \
    --group-directories-first \
    "$1"
}

preview::text-file() {
  local file="$1" line_number="$2"
  file="${file/#\~\//$HOME/}" # expand ~

  local bat_bin
  if ! bat_bin=$(bat::bin-path)
  then
    # Fall back to awk
    awk -v ln="${line_number:-1}" \
      'NR==int(ln) {$0="\033[31m" $0 "\033[0m"} 1' \
      "$file"
    return "$?"
  fi

  local bat_extra_args=()

  if [[ -n "$line_number" && "$line_number" -gt -1 ]]
  then
    bat_extra_args+=(--highlight-line="$line_number")
  fi

  # assume stuff in ZDOTDIR is zsh
  if [[ "$(realpath "$file")" =~ ^${ZDOTDIR} ]]
  then
    bat_extra_args+=(--language zsh)
  fi

  "${bat_bin}" \
    --color=always \
    --style="${BAT_STYLE:-numbers}" \
    --pager=never \
    --style=header-filename \
    "${bat_extra_args[@]}" \
    "$file"
}

main() {
  case "$1" in
    -h|--help)
      # Check if there's an actual file named -h or --help
      if [[ ! -e "$1" ]]
      then
        usage
        exit 0
      fi
      ;;
  esac

  local file="$1"

  if [[ -z "$file" ]]
  then
    echo "Missing FILE argument" >&2
    usage >&2
    return 2
  fi

  local line_number
  if [[ ! -e "$file" ]]
  then
    local file2
    read -r file2 line_number <<<"$(sed -nr 's#(.+):([0-9]+)#\1 \2#p' <<< "$file")"

    if [[ ! -e "$file2" ]]
    then
      echo "File2 not found: $file"
      return 1
    fi

    file="$file2"

    if [[ -n "$line_number" && ! "$line_number" =~ ^[0-9] ]]
    then
      echo "Invalid line number: $line_number"
      return 1
    fi
  fi

  local mimetype
  mimetype=$(mimetype "$file")

  case "$mimetype" in
    inode/directory)
      preview::directory "$file"
      ;;
    image/*)
      preview::image "$file"
      ;;
    *binary*)
      preview::binary "$file"
      ;;
    *)
      preview::text-file "$file" "$line_number"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
  exit "$?"
fi
