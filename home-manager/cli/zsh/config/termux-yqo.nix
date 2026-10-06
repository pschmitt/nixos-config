''
  unalias yqo 2>/dev/null || true
  yqo() {
    local query="$1" verbatim

    case "$1" in
      help|h|-h|--help)
        print -r -- "Usage: $0 CMD"
        return 0
        ;;
      --verbatim|-n)
        verbatim=1
        query="$2"
        ;;
    esac

    if [[ -z "$query" ]]
    then
      print -ru2 -- "Missing CMD"
      return 2
    fi

    if [[ -z "$verbatim" ]] && whence -p -- "$1" >/dev/null
    then
      query="$(whence -p -- "$1")"
    fi

    print -r -- "Looking for: $query"
    command dpkg -S "$query"
  }
''
