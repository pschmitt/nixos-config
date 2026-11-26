# OSC 7: report the working directory to the terminal (new tabs and splits
# open there). Shared by the Home Manager and the NixOS-level Zsh config.
__osc7-pwd() {
  emulate -L zsh
  setopt extendedglob
  local LC_ALL=C encoded
  encoded=${PWD//(#m)([^@-Za-z&-;_~])/%${(l:2::0:)$(([##16]#MATCH))}}
  printf '\e]7;file://%s%s\e\\' "$HOST" "$encoded"
}

__chpwd-osc7-pwd() {
  (( ZSH_SUBSHELL )) || __osc7-pwd
}

__chpwd-osc7-pwd
chpwd_functions+=(__chpwd-osc7-pwd)
