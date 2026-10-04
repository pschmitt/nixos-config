{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  updateAndDeploy = pkgs.writeShellApplication {
    name = "update-and-deploy";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.just
      pkgs.nix
    ];
    text = builtins.readFile ../../../../scripts/update-and-deploy.sh;
  };
in
{
  home.packages = lib.optionals (!termuxMode) [ updateAndDeploy ];

  programs.zsh.initContent = lib.mkOrder 520 ''
    if [[ -n "''${DISTROBOX_ENTER_PATH:-}" && "$TERM" == wezterm ]]
    then
      export TERM=xterm-256color
    fi

    os-release::value() {
      local key="$1" value
      [[ -r /etc/os-release ]] || return 1
      value="$(. /etc/os-release; print -r -- "''${(P)key}")"
      [[ -n "$value" ]] || return 1
      print -r -- "$value"
    }

    os-release::is() {
      local key=ID
      if (( $# > 1 )); then
        key="$1"
        shift
      fi
      [[ "$(os-release::value "''${key:u}")" == "$1" ]]
    }

    os-release::kind() {
      if is_termux
      then
        print -r -- termux
        return 0
      fi

      case "$(os-release::value ID)" in
        neon|ubuntu) print -r -- ubuntu ;;
        arch|archarm|manjaro) print -r -- arch ;;
        fedora) print -r -- fedora ;;
        alpine|postmarketos) print -r -- alpine ;;
        *) os-release::value ID ;;
      esac
    }

    is_termux() {
      [[ "''${TERMUX_RUN_MODE:-}" == ci ]] && return 0
      [[ "$OSTYPE" == *android* ]] && (( $+commands[termux-info] ))
    }

    is_nixos() { os-release::is nixos || [[ -e /etc/NIXOS ]] }
    is_archlinux() { [[ "$(os-release::kind)" == arch ]] }
    is_postmarketos() { [[ "$(os-release::kind)" == alpine && "$(os-release::value ID)" == postmarketos ]] }
    is_fedora() { [[ "$(os-release::kind)" == fedora ]] }
    is_ubuntu() { [[ "$(os-release::kind)" == ubuntu ]] }
    is_distrobox() { [[ -n "''${DISTROBOX_ENTER_PATH:-}" ]] }
    in_flatpak() { [[ "''${container:-}" == flatpak ]] }
    not_in_vt() {
      tty 2>/dev/null | grep -vq /dev/tty && \
        ! [[ "$TERM" =~ vt.* ]] && \
        ! [[ "$TERM" == linux ]]
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

    libc::version-at-least() {
      [[ $# == 1 ]] || return 2
      local current
      current="$(ldd --version 2>/dev/null | awk 'NR == 1 { print $NF }')" || return 1
      [[ -n "$current" ]] || return 1
      version::at-least "$1" "$current"
    }

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
      version::at-least "$current" "$1"
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

    echo_info() { print -r -- "$*" }
    echo_err() { print -ru2 -- "$*" }
    echo_error() { echo_err "$@" }
    echo_warning() { echo_err "$@" }
    echo_debug() { [[ -n "''${DEBUG:-}" ]] && print -ru2 -- "$*" }
    echo_ok() { print -r -- "$*" }
    echo_confirm() {
      print -n -u2 -- "$* [y/N] "
      read -rq REPLY
      print -u2
      [[ "$REPLY" == [Yy] ]]
    }

    yup() {
      if is_termux
      then
        command pkg upgrade "$@"
      else
        command update-and-deploy "$@"
      fi
    }

    yupnc() {
      if is_termux
      then
        command pkg upgrade -y "$@"
      else
        yup --flake-update --print-build-logs "$@"
      fi
    }

    yqo() {
      case "$(os-release::kind)" in
        arch)
          command yay -Qo "$@"
          ;;
        fedora)
          command dnf provides "$@"
          ;;
        ubuntu)
          local usage="Usage: $0 [--verbatim|-n] CMD"
          if (( $# == 0 ))
          then
            print -ru2 -- "$usage"
            return 2
          fi

          if [[ "$1" == (help|h|-h|--help) ]]
          then
            print -r -- "$usage"
            return 0
          fi

          local query="$1" command_path
          if [[ "$query" == --verbatim || "$query" == -n ]]
          then
            shift
            if (( $# == 0 ))
            then
              print -ru2 -- 'Missing CMD'
              return 2
            fi
            query="$1"
          elif command_path="$(whence -p -- "$query" 2>/dev/null)" && [[ -n "$command_path" ]]
          then
            query="$command_path"
          fi

          print -r -- "Looking for: $query"
          command dpkg -S "$query"
          ;;
        *)
          command nix-env --query "$@"
          ;;
      esac
    }

    yrm() {
      local -a packages=("$@")
      (( ''${#packages} )) || return 2
      if command nix-env -e "''${packages[@]}"
      then
        command nix-collect-garbage --delete-older-than 7d
      fi
    }
  '';
}
