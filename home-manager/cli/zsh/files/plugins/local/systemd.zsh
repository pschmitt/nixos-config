# systemd
(( $+commands[systemctl] )) || return

# completions
if [[ -z "$NO_COMPLETIONS" ]]
then
  CUSTOM_COMPS[sc-cat-execstart]="systemctl cat"
  CUSTOM_COMPS[sc-cat-field]="systemctl cat"
  CUSTOM_COMPS[sc-devel]="systemctl status"
  CUSTOM_COMPS[sc-unit-path]="systemctl cat"
  CUSTOM_COMPS[sc-vim]="systemctl edit"
  CUSTOM_COMPS[scu-cat-execstart]="systemctl --user cat"
  CUSTOM_COMPS[scu-cat-field]="systemctl --user cat"
  CUSTOM_COMPS[scu-devel]="systemctl --user status"
  CUSTOM_COMPS[scu-unit-path]="systemctl --user cat"
  CUSTOM_COMPS[scu-vim]="systemctl --user edit"
  CUSTOM_COMPS[sc-restart-with-logs]="systemctl restart"
  CUSTOM_COMPS[sc-start-with-logs]="systemctl start"
  CUSTOM_COMPS[scu-restart-with-logs]="systemctl --user restart"
  CUSTOM_COMPS[scu-start-with-logs]="systemctl --user start"
fi

alias sc="sudo systemctl"

# Legacy commands. Use sc-start, sc-stop etc instead (OMZP::systemd)
# alias start="sudo systemctl start"
# alias stop="sudo systemctl stop"
# alias restart="sudo systemctl restart"
# alias status="sudo systemctl status"
# /!\ enable and disable are builtin commands!
# alias enable="sudo systemctl enable"
# alias disable="sudo systemctl disable"

alias sc-ls-enabled="systemctl list-unit-files | \
  awk '\$2 == \"enabled\" { print \$1 }'"
alias scu-ls-enabled="systemctl list-unit-files --user | \
  awk '\$2 == \"enabled\" { print \$1 }'"
alias sc-ls-failed="sudo systemctl --failed"
alias scu-ls-failed="sudo systemctl --failed --user"

() {
  for action in start stop restart
  do
    eval "sc-$action-with-logs() {
      systemctl::action-with-logs-wrapper '$action' \"\$@\"
    }"
    eval "scu-$action-with-logs() {
      systemctl::action-with-logs-wrapper --user '$action' \"\$@\"
    }"
  done
}

alias scu-devel="sc-devel --user"

alias scu-unit-path="sc-unit-path --user"
alias scu-cat-field="sc-cat-field --user"
alias scu-cat-execstart="sc-cat-execstart --user"
alias scu-vim="sc-vim --user"
