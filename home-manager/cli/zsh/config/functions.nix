{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  # The OS is known when the config is built: Termux bundles are Termux and
  # NixOS-integrated Home Manager runs on NixOS. Only containers/distroboxes
  # sharing this home (or unknown hosts) need runtime /etc/os-release parsing.
  staticOsKind =
    if termuxMode then
      "termux"
    else if config.submoduleSupport.enable then
      "nixos"
    else
      null;
  termuxYqo = import ./termux-yqo.nix;
  genericYqo = ''
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
  '';
  yqoInit = if termuxMode then termuxYqo else genericYqo;
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

    # Parse /etc/os-release once into __OS_RELEASE and derive __OS_KIND. Only
    # needed at runtime for os-release::value or when the OS is not static.
    os-release::load() {
      (( ''${+__OS_RELEASE} )) && return 0
      setopt localoptions extendedglob
      typeset -gA __OS_RELEASE
      typeset -g __OS_KIND=
      local line
      if [[ -r /etc/os-release ]]
      then
        while IFS= read -r line
        do
          [[ "$line" == [A-Za-z_][A-Za-z0-9_]#=* ]] || continue
          __OS_RELEASE[''${line%%=*}]="''${(Q)line#*=}"
        done < /etc/os-release
      fi

      ${lib.optionalString termuxMode ''
        __OS_KIND=termux
        return 0
      ''}
      ${lib.optionalString (!termuxMode) ''
        if is_termux
        then
          __OS_KIND=termux
          return 0
        fi
      ''}

      case "''${__OS_RELEASE[ID]}" in
        neon|ubuntu) __OS_KIND=ubuntu ;;
        arch|archarm|manjaro) __OS_KIND=arch ;;
        fedora) __OS_KIND=fedora ;;
        alpine|postmarketos) __OS_KIND=alpine ;;
        *) __OS_KIND="''${__OS_RELEASE[ID]}" ;;
      esac
    }

    os-release::value() {
      os-release::load
      [[ -n "''${__OS_RELEASE[$1]}" ]] || return 1
      print -r -- "''${__OS_RELEASE[$1]}"
    }

    os-release::is() {
      local key=ID
      if (( $# > 1 )); then
        key="$1"
        shift
      fi
      os-release::load
      [[ "''${__OS_RELEASE[''${key:u}]}" == "$1" ]]
    }

    os-release::kind() {
      [[ -n "''${__OS_KIND:-}" ]] || os-release::load
      [[ -n "$__OS_KIND" ]] || return 1
      print -r -- "$__OS_KIND"
    }

    is_termux() {
      ${
        if termuxMode then
          "return 0"
        else
          ''
            # Static: a non-Termux build never runs in Termux; CI exercises
            # the Termux paths on Linux.
            [[ "''${TERMUX_RUN_MODE:-}" == ci ]]
          ''
      }
    }

    is_nixos() { [[ "$__OS_KIND" == nixos || -e /etc/NIXOS ]] }
    is_archlinux() { [[ "$__OS_KIND" == arch ]] }
    is_postmarketos() { os-release::is postmarketos }
    is_fedora() { [[ "$__OS_KIND" == fedora ]] }
    is_ubuntu() { [[ "$__OS_KIND" == ubuntu ]] }
    is_distrobox() { [[ -n "''${DISTROBOX_ENTER_PATH:-}" ]] }
    in_flatpak() { [[ "''${container:-}" == flatpak ]] }
    not_in_vt() {
      [[ "''${TTY:-}" != /dev/tty* && "$TERM" != vt* && "$TERM" != linux ]]
    }

    ${
      if staticOsKind != null then
        ''
          if is_distrobox || [[ -e /run/.containerenv || -e /.dockerenv ]]
          then
            os-release::load
          else
            typeset -g __OS_KIND=${staticOsKind}
          fi
        ''
      else
        "os-release::load"
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

    # The yadm lib set this as a side effect of tmux::version-at-least;
    # plugins use it at load time (aliases like whatswrong).
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

    # stderr, like the yadm echo:: helpers: functions whose stdout is
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

    yup() {
      ${
        if termuxMode then
          ''
            command pkg upgrade "$@"
          ''
        else
          ''
            command update-and-deploy "$@"
          ''
      }
    }

    yupnc() {
      ${
        if termuxMode then
          ''
            command pkg upgrade -y "$@"
          ''
        else
          ''
            yup --flake-update --print-build-logs "$@"
          ''
      }
    }

    ${yqoInit}

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
