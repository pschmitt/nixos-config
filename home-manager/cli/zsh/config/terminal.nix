{ lib, ... }:
{
  programs.zsh.initContent = lib.mkOrder 1450 ''
    if [[ "$(os-release::kind)" == fedora && -r /etc/profile.d/vte.sh ]]
    then
      () {
        local TERM=xterm VTE_VERSION=99999
        source /etc/profile.d/vte.sh
      }
    fi

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
  '';
}
