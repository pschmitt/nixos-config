{ lib, ... }:
{
  programs.vivid.activeTheme = lib.mkForce "catppuccin-mocha";

  programs.zsh = {
    shellAliases = {
      y = lib.mkForce "apt search";
      ync = lib.mkForce "pkg install -y";
      yqq = lib.mkForce "apt-cache policy";
      yrm = lib.mkForce "pkg remove -y";
    };

    envExtra = ''
      typeset -U path
      path=(
        "$HOME/bin"
        "$CARGO_HOME/bin"
        "$GOPATH/bin"
        "$XDG_DATA_HOME/luarocks/bin"
        "$HOME/.local/bin"
        "$XDG_DATA_HOME/krew/bin"
        "$XDG_DATA_HOME/asdf/shims"
        "$XDG_DATA_HOME/npm/bin"
        $path
      )

      if (( $+commands[termux-info] ))
      then
        path+=(/system/bin)
        path=("''${(@)path:#/bin}")

        export XDG_DOCUMENTS_DIR="$HOME/storage/shared/Documents"
        export XDG_DOWNLOAD_DIR="$HOME/storage/shared/Download"
        export XDG_MUSIC_DIR="$HOME/storage/shared/Music"
        export XDG_PICTURES_DIR="$HOME/storage/shared/Pictures"
        export XDG_VIDEOS_DIR="$HOME/storage/shared/Videos"
        if [[ -d "$HOME/storage" ]]
        then
          export XDG_DOWNLOAD_DIR="$HOME/storage/downloads"
          export XDG_PICTURES_DIR="$HOME/storage/pictures"
        fi
      fi
    '';

    initContent = lib.mkMerge [
      (lib.mkOrder 600 ''
        if is_termux
        then
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

          ping() {
            local -a ipv4 ipv6
            zparseopts -E -D 4=ipv4 6=ipv6

            if (( ''${#ipv6} ))
            then
              command ping6 "$@"
            else
              command ping "$@"
            fi
          }
        fi
      '')
      (lib.mkOrder 615 ''
        if is_termux && (( $+functions[hashdir] ))
        then
          [[ -d "$XDG_DOCUMENTS_DIR" ]] && hashdir "$XDG_DOCUMENTS_DIR" docs
          [[ -d "$XDG_DOCUMENTS_DIR/notes" ]] && hashdir "$XDG_DOCUMENTS_DIR/notes" notes
          [[ -d "$XDG_PICTURES_DIR" ]] && hashdir "$XDG_PICTURES_DIR" pics
        fi
      '')
      (lib.mkOrder 620 ''
        if is_termux && (( $+commands[yadm] ))
        then
          () {
            local class classes changed
            classes="$(yadm config --get-all local.class)"

            for class in termux notnixos
            do
              if ! grep -qx "$class" <<< "$classes"
              then
                yadm config --add local.class "$class"
                changed=1
              fi
            done

            if [[ -n "$changed" ]]
            then
              yadm alt
            fi
          }
        fi
      '')
    ];
  };
}
