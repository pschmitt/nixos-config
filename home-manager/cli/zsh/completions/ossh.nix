{ lib, pkgs, ... }:
let
  completion = pkgs.linkFarm "zsh-completion-ossh" [
    {
      name = "_ossh";
      path = pkgs.writeText "zsh-completion-ossh" ''
        #compdef ossh

        _ossh_context_from_words() {
          local index

          for (( index = 1; index <= $#words; index++ ))
          do
            if [[ "''${words[index]}" == "--context" ]] && (( index < $#words ))
            then
              print -r -- "''${words[index + 1]}"
              return 0
            fi
          done

          return 1
        }

        _ossh() {
          local curcontext="$curcontext"
          local state
          local -a contexts hosts
          local helper="''${HOME}/.config/ssh/bin/openstack-vm-proxy.sh"

          _arguments -C \
            '(-h --help)'{-h,--help}'[show help]' \
            '--context[OpenStack Kubernetes context]:context:->contexts' \
            '1:vm:->hosts' \
            '*:remote command:_command_names' || return 0

          case "$state" in
            contexts)
              contexts=( "''${(@f)$("$helper" --list-contexts 2>/dev/null)}" )
              _describe -t contexts 'context' contexts
              ;;
            hosts)
              local ctx
              ctx="$( _ossh_context_from_words )"
              if [[ -n "$ctx" ]]
              then
                hosts=( "''${(@f)$("$helper" --context "$ctx" --list-hosts 2>/dev/null)}" )
              else
                hosts=( "''${(@f)$("$helper" --list-hosts 2>/dev/null)}" )
              fi
              _describe -t openstack_vms 'OpenStack VM' hosts
              ;;
          esac
        }
      '';
    }
  ];
in
{
  programs.zsh.initContent = lib.mkOrder 520 ''
    fpath=(${completion} $fpath)
  '';
}
