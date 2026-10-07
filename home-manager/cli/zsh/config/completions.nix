{ lib, ... }:
{
  programs.zsh = {
    setOptions = [
      "ALWAYS_TO_END"
      "AUTO_MENU"
      "COMPLETE_IN_WORD"
      "CORRECT"
      "CORRECT_ALL"
    ];

    initContent = lib.mkOrder 1000 ''
      WORDCHARS=
      zmodload zsh/complist
      autoload -Uz bashcompinit
      bashcompinit

      if [[ -z "$NO_COMPLETIONS" && ! -o nointeractive && -z "''${_comps+x}" ]]
      then
        autoload -Uz compaudit compinit
        () {
          # Reuse the dump (compinit -C skips compaudit and the function scan)
          # while fpath is unchanged -- store paths change on every rebuild --
          # and no writable fpath dir is newer than the dump.
          local dump="$ZSH_COMPDUMP" key="''${(j.:.)fpath}" saved dir fresh=0
          if [[ -s "$dump" && -r "$dump.fpath" ]] && IFS= read -r saved < "$dump.fpath" && [[ "$saved" == "$key" ]]
          then
            fresh=1
            for dir in $fpath
            do
              [[ "$dir" == /nix/store/* || ! "$dir" -nt "$dump" ]] && continue
              fresh=0
              break
            done
          fi
          if (( fresh ))
          then
            compinit -C -d "$dump"
            return
          fi

          # compinit only rebuilds an existing dump when the number of
          # completion files changed; a rename (_adb -> _adb.sh) kept the
          # stale one. fpath or a writable dir changed: start from scratch.
          [[ -e "$dump" ]] && command rm -f -- "$dump" "$dump.zwc"

          local audit_output audit_dir
          local -a insecure_paths
          audit_output="$(compaudit 2>/dev/null || true)"
          for audit_dir in "''${(@f)audit_output}"
          do
            [[ -d "$audit_dir" && "$audit_dir" != /nix/store ]] && insecure_paths+=("$audit_dir")
          done

          if (( ''${#insecure_paths} == 0 ))
          then
            # Nix store entries are immutable even though /nix/store is group-writable.
            compinit -u -d "$ZSH_COMPDUMP"
          else
            compinit -d "$ZSH_COMPDUMP"
          fi
          print -r -- "$key" >| "$dump.fpath"
        }
      fi

      zstyle ':completion:*' completer _complete _expand _prefix _ignored _correct _approximate
      zstyle ':completion:*' use-cache on
      zstyle ':completion:*:cache-path' "''${XDG_CACHE_HOME}/zsh"
      zstyle ':completion:*' menu select=2
      zstyle ':completion:*' matcher-list "" 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' '+l:|=* r:|=*'
      zstyle ':completion:*:approximate:*' max-errors 2 numeric
      zstyle ':completion:*' verbose yes
      zstyle ':completion:*:parameters' extra-verbose yes
      zstyle ':completion:*' special-dirs true
      zstyle ':completion:*' squeeze-slashes true
      zstyle '*' single-ignored show
      zstyle -e ':completion:*:warnings' format autocomplete:config:format:warnings
      autocomplete:config:format:warnings() {
        [[ $CURRENT == 1 && -z $PREFIX$SUFFIX ]] ||
          reply=( $'%{\e[0;2m%}'"no matching %d completions"$'%{\e[0m%}' )
      }
      zstyle ':completion:*:messages' format '%F{9}%d%f'
      zstyle ':completion:*:descriptions' format $'%{\e[0;1;2m%}%d%{\e[0m%}'
      zstyle ':completion:*:*:*:*:corrections' format '%F{yellow}%d (errors: %e)%f'
      zstyle ':completion:*:default' select-prompt '%F{black}%K{12}line %l %p%f%k'
      zstyle ':completion:*:processes' command 'ps -ax'
      zstyle ':completion:*:processes-names' command 'ps -aeo comm='
      zstyle ':completion:*:*:kill:*' menu yes select
      zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
      zstyle ':completion:*:*:killall:*' menu yes select
      zstyle ':completion:*:*:killall:*:processes-names' list-colors '=(#b) #([0-9]#)*=0=01;31'
      zstyle ':completion:*:functions' ignored-patterns '_*'
      zstyle ':completion:*' rehash true
      zstyle ':completion:*:manuals' separate-sections true
      zstyle ':completion:*:manuals.*' insert-sections true
      zstyle ':completion:*:man:*' menu yes select

      if [[ -z "$NO_COMPLETIONS" ]]
      then
        source "$ZDOTDIR/completions/source-me.zsh" 2>/dev/null
        (( $+functions[compdef] )) && compdef _kubectl kubectl kubecolor
      fi

      compdefas() {
        (( $+_comps[$1] )) && compdef $_comps[$1] ''${^@[2,-1]}=$1
      }

      _as_if() {
        local words=("$words[@]") CURRENT=$CURRENT
        words[1]="$@"
        (( CURRENT += $# - 1 ))
        _normal
      }

      compdef_asif() {
        local cmd1=( ''${=1} )
        shift
        local cmd2=( ''${=*} )
        [[ -n "$cmd1" && -n "$cmd2" ]] && compdef "_as_if $cmd2" "$cmd1"
      }

      __init_custom_completions() {
        local key val
        local -a val_arr
        for key val in ''${(kv)CUSTOM_COMPS} ''${(kv)CUSTOM_COMPS_STATIC}; do
          val_arr=( ''${=val} )
          if (( ''${#val_arr} > 1 )); then
            compdef_asif "$key" "$val"
          else
            compdefas "$val" "$key"
          fi
        done
      }
      __init_custom_completions
    '';
  };
}
