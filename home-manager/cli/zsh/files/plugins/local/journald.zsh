# journalctl
alias jxf="sudo journalctl -xfl"
alias jb="sudo journalctl -bl"
alias jerr="sudo journalctl -b -p err" # Only show errors since last boot
alias ju="sudo journalctl -l -u" # By unit
alias jcat="sudo journalctl --output cat"

# NOTE jc is already taken by https://github.com/kellyjonbrazil/jc
alias jl="sudo journalctl"
alias jc-id="journalctl -xlf --identifier"
alias jc-unit="sudo journalctl -xlf -u"
alias jc-errors="sudo journalctl -b -p err"
alias jc-errors-unit="sudo journalctl -xlf -p err -u"

# user
alias jcu="journalctl --user"
alias jcu-cat="journalctl --user --output cat"
alias jcu-unit="journalctl --user -xlf -u"
alias jcu-id="journalctl --user --identifier"
alias jcu-errors="journalctl --user -b -p err"
alias jcu-errors-unit="journalctl --user -xlf -p err -u"

# completions
if [[ -z "$NO_COMPLETIONS" ]]
then
  CUSTOM_COMPS[journalctl::since-unit-active]="systemctl cat"
  CUSTOM_COMPS[journalctl::last-run]="systemctl cat"
fi

