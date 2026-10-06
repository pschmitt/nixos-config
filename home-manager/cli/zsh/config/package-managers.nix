{ lib, ... }:
{
  programs.zsh.initContent = lib.mkOrder 1150 ''
    case "$__OS_KIND" in
      nixos)
        alias y='nix search nixpkgs'
        alias ync='nix-shell --packages'
        alias yqo='nix-env --query'

        yup() {
          command update-and-deploy "$@"
        }

        yupnc() {
          yup --flake-update --print-build-logs "$@"
        }

        function yrm() {
          if (( $# == 0 ))
          then
            print -ru2 -- 'Usage: yrm PACKAGE...'
            return 2
          fi

          nix-env --uninstall "$@" || return
          nix-collect-garbage --delete-older-than 7d
        }
        ;;
      arch)
        alias y='yay'
        alias yasdep='yay -S --asdeps'
        alias ycl='yay -Scc'
        alias ylu='sudo rm -rf /var/lib/pacman/db.lck'
        alias ync='yay -S --noconfirm'
        alias yqq='yay -Q'
        alias yqo='yay -Qo'
        alias yrm='yay -Rsn'
        alias yrf='yay -Rcsn'
        alias yu='yay -U'
        alias yup='yay -Syu --batchinstall'
        alias yupnc='yay -Syu --noconfirm --batchinstall'
        ;;
      fedora)
        alias y='dnf search'
        alias ync='sudo dnf install -y'
        alias yrm='sudo dnf remove -y'
        alias yqo='dnf provides'
        alias yupnc='sudo dnf upgrade --refresh -y'

        package::query() {
          if (( $# != 1 ))
          then
            print -ru2 -- "Usage: $0 NAME"
            return 2
          fi

          local package_list result
          package_list="$(dnf list installed)" || return
          result="$(awk -v package="$1" 'index($1, package ".") == 1 { print $1, $2 }' <<< "$package_list")"

          if [[ -n "$result" ]]
          then
            print -r -- "$result"
            return 0
          fi

          print -ru2 -- "No package named \"$1\" found!"
          print -ru2 -- 'Possible matches:'
          print -r -- "$package_list" | awk -v package="$1" 'index($1, package) == 1 { print $1 }' | sed -E 's/\..+//' >&2
          return 1
        }
        ;;
      ubuntu)
        alias y='apt search'
        alias ync='sudo apt install -y'
        alias yrm='sudo apt remove -y'

        alias yqq='apt-cache policy'
        if os-release::is ID neon
        then
          alias yupnc='sudo pkcon update -y'
        else
          alias yupnc='sudo apt update && sudo apt upgrade -y'
        fi
        ;;
      alpine)
        alias y='apk search'
        alias ync='sudo apk add'
        alias yqq='apk -vv info | grep -i'
        alias yrm='sudo apk del'
        alias yupnc='sudo apk update && sudo apk upgrade'
        ;;
    esac
  '';
}
