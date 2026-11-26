
# nmap
if (( ! $+commands[nmap] ))
then
  alias nmap=nmap-for-poor-people
  return
fi

if (( $+commands[grc] ))
then
  alias nmap="grc nmap"
fi

# completions
if [[ -z "$NO_COMPLETIONS" ]]
then
  CUSTOM_COMPS[wnmap]=nmap
fi
