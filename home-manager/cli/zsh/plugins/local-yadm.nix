{ lib, ... }:
{
  programs.zsh.initContent = lib.mkOrder 1360 ''
    zsh::override-local-yadm() {
      unset 'CUSTOM_COMPS[zi::jd]'

      yadm::classes() {
        local help
        zparseopts -D -E -K -- \
          {h,-help}=help

        if [[ -n "$help" ]]
        then
          print -u2 'Usage: yadm::classes'
          print -u2 'List the classes configured for this yadm repository.'
          return 0
        fi

        if (( $# > 0 ))
        then
          print -u2 'Usage: yadm::classes'
          return 2
        fi

        yadm config --get-all local.class
      }

      yadm::class-add() {
        local help class classes
        zparseopts -D -E -K -- \
          {h,-help}=help

        if [[ -n "$help" ]]
        then
          print -u2 'Usage: yadm::class-add CLASS'
          print -u2 'Add a class and reapply yadm alternates.'
          return 0
        fi

        if (( $# != 1 )) || [[ -z "$1" ]]
        then
          print -u2 'Usage: yadm::class-add CLASS'
          return 2
        fi

        class="$1"
        classes="$(yadm config --get-all local.class 2>/dev/null || :)"
        if grep -qxF -- "$class" <<< "$classes"
        then
          return 0
        fi

        yadm config --add local.class "$class" || return
        yadm alt
      }

      yadm::class-remove() {
        local help class classes
        zparseopts -D -E -K -- \
          {h,-help}=help

        if [[ -n "$help" ]]
        then
          print -u2 'Usage: yadm::class-remove CLASS'
          print -u2 'Remove a class and reapply yadm alternates.'
          return 0
        fi

        if (( $# != 1 )) || [[ -z "$1" ]]
        then
          print -u2 'Usage: yadm::class-remove CLASS'
          return 2
        fi

        class="$1"
        classes="$(yadm config --get-all local.class 2>/dev/null || :)"
        if ! grep -qxF -- "$class" <<< "$classes"
        then
          return 0
        fi

        yadm config --fixed-value --unset-all local.class "$class" || return
        yadm alt
      }

      yadm::pull() {
        local decrypt lazy_update force verbose
        zparseopts -D -E -K -- \
          {d,-decrypt}=decrypt \
          {u,l,-lazy-update}=lazy_update \
          {f,-force}=force \
          {v,-verbose}=verbose

        local rev="$(yadm rev-parse HEAD)"
        if ! yadm pull --rebase --autostash
        then
          return 1
        fi

        local new_rev="$(yadm rev-parse HEAD)"
        if [[ "$rev" != "$new_rev" ]]
        then
          yadm log --oneline --no-merges "''${rev}..''${new_rev}"
        elif [[ -z "$force" ]]
        then
          return 0
        fi

        if ! is_distrobox
        then
          if [[ -n "$verbose" ]]
          then
            yadm alt
          else
            yadm alt &>/dev/null
          fi
        fi

        if [[ -n "$decrypt" ]] || \
           yadm diff --name-only "$rev" "$new_rev" | \
             grep -qE '^.local/share/yadm/archive$'
        then
          if gpg::is-unlocked
          then
            yadm decrypt
          else
            echo_warning 'GPG key is not unlocked, skipping decryption'
          fi
        fi

        if [[ -n "$lazy_update" ]]
        then
          vim::lazy-update
        fi

        if is_termux
        then
          termux::fix-mason-nvim-binaries
        fi

        print -r -- 'Nix-managed shell dependencies update with the next Home Manager rebuild.'

        [[ -o interactive ]] || return 0
        zsh::source-local-plugins
      }

      # Keep the Yadm submodule helper while Nix handles shell plugin updates.
      yadm::pull-and-update-submodules() {
        yadm pushall && \
          yadm pull --rebase --autostash && \
          tmux-slay run -n yadm-update -b -c -u -t 30 \
          "yadm submodule foreach \
            'git submodule update --init --recursive; \
             git checkout master; \
             git pull;'"
      }
    }
  '';
}
