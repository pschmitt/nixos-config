alias teecat="tee >(cat)"
alias teecaterr="tee >(cat >&2)"

alias pf="printf %s"

typeset -Ag MSG_COLORS=(
  [default]=${fg[default]}
  [success]=${fg[green]}
  [error]=${fg[red]}
  [warning]=${fg[yellow]}  # that looks orange to me
  [pending]='\e[38;5;006m'
  [debug]=${fg[magenta]}
  [info]=${fg[blue]}
  [dryrun]=${fg[cyan]}
)

typeset -Ag MSG_PREFIX=(
  [default]=""
  [success]="OK"
  [error]="ERR"
  [warning]="WRN"
  [pending]="PND"
  [debug]="DBG"
  [info]="INF"
  [dryrun]="DRY"
)

typeset -Ag MSG_EMOJI=(
  [default]=""
  [success]="✅"
  [error]="⛔"
  [warning]="🚸"
  [pending]="👷"
  [debug]="🐛"
  [info]="🔹"
  [dryrun]="🦺"
)

typeset -Ag ECHO_LEVELS=(
  [debug]=1
  [info]=2
  [dryrun]=2
  [warning]=3
  [none]=99
)

export ECHO_LEVEL="${ECHO_LEVELS[${ECHO_LEVEL:-debug}]}"

zsh::autoload-dir echo

# function aliases
() {
  local al
  local func
  local -a aliases_debug=(d)
  local -a aliases_error=(e err fail failure)
  local -a aliases_info=(i)
  local -a aliases_success=(ok)
  local -a aliases_pending=(p progress)
  local -a aliases_warning=(w warn)

  # FIXME Iterate over debug failure info.. instead of *alias_*debug etc.
  # ${(P)aliases_${(P)func}}[@] does not work.
  for func in aliases_debug \
              aliases_error \
              aliases_info \
              aliases_success \
              aliases_pending \
              aliases_warning
  do
    for al in ${${(P)func}[@]}
    do
      # logger "DECLARE echo_$al -> echo_${func##aliases_}"
      falias echo::${al} echo::${func##aliases_}
    done
  done
}

# alias echo::* to echo_*
() {
  local func func_new
  for func in ${(kM)functions:#echo::*}
  do
    func_new=${func//echo::/echo_}
    (( ${+functions[$func_new]} )) && continue

    falias $func_new $func
  done
}
