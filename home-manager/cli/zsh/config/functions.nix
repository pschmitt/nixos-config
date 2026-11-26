{
  config,
  lib,
  ...
}:
{
  programs.zsh.initContent = lib.mkOrder 520 ''
    is_nixos() { [[ -e /etc/NIXOS ]] }
    not_in_vt() {
      [[ "''${TTY:-}" != /dev/tty* && "$TERM" != vt* && "$TERM" != linux ]]
    }

    falias() {
      local usage="Usage: $0 ALIAS FUNCTION" alias_name function_name
      local -a strict
      zparseopts -D -K s=strict -strict=strict
      alias_name="$1"
      function_name="$2"
      if [[ -z "$alias_name" || -z "$function_name" ]]; then
        print -ru2 -- "$usage"
        return 2
      elif [[ "$alias_name" == --help || "$alias_name" == -h ]]; then
        print -r -- "$usage"
        return 0
      fi
      if (( ''${#strict} )) && (( ! $+commands[$function_name] )) && (( ! $+functions[$function_name] )); then
        print -ru2 -- "command not found (yet?): $function_name"
        return 1
      fi
      eval "$alias_name() { \"$function_name\" \"\$@\"; }"
    }

    multisrc() {
      local file
      for file in "$@"
      do
        [[ -r "$file" ]] && source "$file"
      done
    }

    pathmunge() {
      (( $path[(Ie)$1] )) && return 0
      if [[ "''${2:-}" == after ]]
      then
        path+=("$1")
      else
        path=("$1" $path)
      fi
    }

    version::at-least() {
      [[ $# == 2 ]] || return 2
      local oldest
      oldest="$(printf '%s\n%s\n' "$1" "$2" | sort --version-sort | head -n 1)"
      [[ "$oldest" == "$1" ]]
    }

    # Plugins use this at load time (aliases like whatswrong).
    typeset -g TMUX_BIN_HOME="''${TMUX_BIN_HOME:-${config.xdg.configHome}/tmux/bin}"

    tmux::version-at-least() {
      [[ $# == 1 ]] || return 2
      local current pid server

      if [[ "$TERM_PROGRAM" == tmux && -n "$TERM_PROGRAM_VERSION" ]]
      then
        current="$TERM_PROGRAM_VERSION"
      elif [[ -n "$TMUX_VERSION" ]]
      then
        current="$TMUX_VERSION"
      elif [[ -n "$TMUX" ]]
      then
        pid="$(command tmux display-message -p '#{pid}' 2>/dev/null)" || return 1
        server="/proc/$pid/exe"
        if [[ -x "$server" ]]
        then
          current="$(command "$server" -V 2>/dev/null)"
          current="''${current#tmux }"
        fi
        if [[ -z "$current" ]]
        then
          current="$(command tmux display-message -p '#{version}' 2>/dev/null)" || return 1
        fi
      else
        current="$(command tmux -V 2>/dev/null)" || return 1
        current="''${current#tmux }"
      fi

      current="''${current#next-}"
      version::at-least "$1" "$current"
    }

    zsh::reload() {
      local signal="''${1:-USR2}"
      pkill -"$signal" -f -- '^-zsh'
    }

    zsh::get-parent-command() {
      ps -f -p "$(awk '{ print $4 }' /proc/$$/stat)" -o command=
    }

    zsh::running-in-guake() {
      local guake_bin
      guake_bin="$(command -v guake)" || return 1
      [[ -n "$guake_bin" ]] && zsh::get-parent-command | grep -qE "$guake_bin"
    }

    suf() {
      "$@"
      unset -f "$1" 2>/dev/null
    }

    source-grep() {
      source <(grep "$@")
    }

    _usage() {
      local func_name=$funcstack[2] func_args=$1
      shift
      local usage="Usage: $func_name $func_args"
      local help
      if [[ -z "$NO_ARGS" && -z "$1" ]]; then
        print -ru2 -- "$usage"
        return 2
      fi
      zparseopts -D -E h=help -help=help
      if [[ -n "$help" ]]; then
        print -r -- "$usage"
        return 87243
      fi
    }

    # stderr, like the echo:: helpers: functions whose stdout is
    # captured (rbw::get in gpg::auto-unlock) must not get these messages.
    echo_info() { print -ru2 -- "$*" }
    echo_err() { print -ru2 -- "$*" }
    echo_error() { echo_err "$@" }
    echo_warning() { echo_err "$@" }
    echo_debug() { [[ -n "''${DEBUG:-}" ]] && print -ru2 -- "$*" }
    echo_ok() { print -ru2 -- "$*" }
    echo_confirm() {
      print -n -u2 -- "$* [y/N] "
      read -rq REPLY
      print -u2
      [[ "$REPLY" == [Yy] ]]
    }
  '';
}
