{ lib, ... }:
{
  # Terminal escapes only belong in interactive shells; `ssh host cmd` and
  # zhj must keep stdout clean (rsync/scp break otherwise).
  programs.zsh.initContent = lib.mkOrder 1450 ''
    if [[ -o interactive ]]
    then
      if is_fedora && [[ -r /etc/profile.d/vte.sh ]]
      then
        () {
          local TERM=xterm VTE_VERSION=99999
          source /etc/profile.d/vte.sh
        }
      fi

      # Delete all Kitty-graphics images (timg -pk, kitten icat, ...) that are
      # left on screen. Pure escape sequence, so no kitty binary is needed.
      # Inside tmux the sequence is wrapped in a DCS passthrough.
      kitty::clear-images() {
        local esc=$'\e'
        local seq="''${esc}_Ga=d,d=A,q=2''${esc}\\"
        {
          if [[ -n "$TMUX" ]]
          then
            printf '\ePtmux;%s\e\\' "''${seq//$esc/$esc$esc}"
          else
            printf '%s' "$seq"
          fi
        } > /dev/tty
      }

      __osc7-pwd() {
        emulate -L zsh
        setopt extendedglob
        local LC_ALL=C encoded
        encoded=''${PWD//(#m)([^@-Za-z&-;_~])/%''${(l:2::0:)$(([##16]#MATCH))}}
        printf '\e]7;file://%s%s\e\\' "$HOST" "$encoded"
      }

      __chpwd-osc7-pwd() {
        (( ZSH_SUBSHELL )) || __osc7-pwd
      }

      __chpwd-osc7-pwd
      chpwd_functions+=(__chpwd-osc7-pwd)
    fi
  '';
}
